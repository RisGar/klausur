import { randomInt } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";

const EXAM_DIR = process.env["EXAM_DIR"] ?? "./assets/";
if (
  !EXAM_DIR ||
  !fs.existsSync(EXAM_DIR) ||
  !fs.statSync(EXAM_DIR).isDirectory()
) {
  console.error(`klausur: directory ${EXAM_DIR} is missing`);
  process.exit(1);
}

const COOKIE_NAME = "klausur";
const COOKIE_MAX_AGE = 60 * 60 * 24 * 365;
const SOCKET_PATH = process.env["KLAUSUR_SOCKET"] ?? "./klausur.sock";

type Paper = { readonly name: string; readonly path: string };

/** A paper to serve, plus the cookie that pins it (new visitors only) */
type Assignment = { readonly paper: Paper; readonly setCookie: string | null };

/** The papers in `directory`, ordered by file name */
const loadPapers = (directory: string): readonly Paper[] =>
  fs
    .readdirSync(directory, { withFileTypes: true })
    .filter(
      (entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".pdf"),
    )
    .map((entry) => ({
      name: entry.name,
      path: path.join(directory, entry.name),
    }))
    .sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));

/** The cookie value for a paper: a hash of its name, so it stays opaque */
const cookieValue = (paper: Paper): string =>
  Bun.hash(paper.name).toString(16).padStart(16, "0");

/** The paper a cookie value points at, if it still exists */
const paperForCookie = (
  papers: readonly Paper[],
  value: string,
): Paper | null => papers.find((paper) => cookieValue(paper) === value) ?? null;

const cookieHeader = (value: string): string =>
  `${COOKIE_NAME}=${value}; Path=/; Max-Age=${COOKIE_MAX_AGE}; SameSite=Lax; Secure; HttpOnly`;

/** The value of our cookie in a `Cookie` header, or "" if there is none. */
const readCookie = (header: string | null): string =>
  (header?.split(";") ?? [])
    .map((part) => part.trim().split("="))
    .filter(([name]) => name === COOKIE_NAME)
    .map(([, ...value]) => value.join("="))
    .at(0) ?? "";

/** Pick a paper uniformly at random for a new visitor */
// Callers only reach this when papers.length > 0 (see the 503 guard)
const randomPaper = (papers: readonly Paper[]): Paper =>
  papers[randomInt(papers.length)]!;

/** The cookie's paper, or a fresh random one pinned in a new cookie */
const assign = (papers: readonly Paper[], cookie: string): Assignment => {
  const existing = paperForCookie(papers, cookie);
  const paper = existing ?? randomPaper(papers);
  return {
    paper,
    setCookie: existing === null ? cookieHeader(cookieValue(paper)) : null,
  };
};

/** Log a new pin, so the journal shows which paper went out */
const logAssignment = (assignment: Assignment): Assignment => {
  if (assignment.setCookie !== null)
    console.log(`klausur: assigned ${assignment.paper.name}`);
  return assignment;
};

const textResponse = (status: number, body: string): Response =>
  new Response(body, {
    status,
    headers: {
      "Content-Type": "text/plain; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });

const pdfResponse = ({ paper, setCookie }: Assignment): Response =>
  new Response(Bun.file(paper.path), {
    status: 200,
    headers: {
      "Content-Type": "application/pdf",
      // Bun.file would otherwise leak the real paper name here
      "Content-Disposition": "inline",
      // the URL is "/" for everybody, so nothing may cache one visitor's paper
      // and hand it to the next one
      "Cache-Control": "no-store, private",
      Vary: "Cookie",
      "X-Robots-Tag": "noindex, nofollow",
      ...(setCookie === null ? {} : { "Set-Cookie": setCookie }),
    },
  });

/** Serve the visitor's paper: the cookie's choice, else a new random one */
const respond = (papers: readonly Paper[], req: Request): Response =>
  papers.length === 0
    ? textResponse(503, "no exam papers configured yet\n")
    : pdfResponse(
        logAssignment(assign(papers, readCookie(req.headers.get("cookie")))),
      );

const papers = loadPapers(EXAM_DIR);

console.log(`klausur: ${papers.length} paper(s) in ${EXAM_DIR}`);

Bun.serve({
  unix: SOCKET_PATH,
  routes: {
    "/": (req) => respond(papers, req),
  },
  fetch: (_req) => textResponse(404, "not found\n"),
});

console.log(`klausur: listening on unix:${SOCKET_PATH}`);
