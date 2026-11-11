"""Tools for researching the CLC26 conference website."""

from __future__ import annotations

from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

CLC_BASE_URL = "https://clc-conference.eu/"
ALLOWED_HOSTS = {"clc-conference.eu", "www.clc-conference.eu"}
MAX_TEXT_CHARS = 20_000
MAX_LINKS = 150
TIMEOUT_SECONDS = 15


class _PageExtractor(HTMLParser):
    _SKIP_TAGS = {"script", "style", "noscript", "svg", "head"}
    _BLOCK_TAGS = {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section", "article"}

    def __init__(self, base_url: str) -> None:
        super().__init__()
        self._base_url = base_url
        self._skip_depth = 0
        self._chunks: list[str] = []
        self._current_href: str | None = None
        self._current_link_text: list[str] = []
        self.links: dict[str, str] = {}

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self._SKIP_TAGS:
            self._skip_depth += 1
        elif tag in self._BLOCK_TAGS:
            self._chunks.append("\n")
        if tag == "a":
            href = dict(attrs).get("href")
            if href and not href.startswith(("#", "mailto:", "javascript:")):
                self._current_href = urljoin(self._base_url, href)
                self._current_link_text = []

    def handle_endtag(self, tag: str) -> None:
        if tag in self._SKIP_TAGS and self._skip_depth:
            self._skip_depth -= 1
        if tag == "a" and self._current_href:
            text = " ".join("".join(self._current_link_text).split())
            if _is_allowed(self._current_href) and self._current_href not in self.links:
                self.links[self._current_href] = text
            self._current_href = None

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        self._chunks.append(data)
        if self._current_href:
            self._current_link_text.append(data)

    @property
    def text(self) -> str:
        lines = (" ".join(line.split()) for line in "".join(self._chunks).splitlines())
        return "\n".join(line for line in lines if line)


def _is_allowed(url: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme in {"http", "https"} and parsed.hostname in ALLOWED_HOSTS


def fetch_clc_page(path_or_url: str = "/") -> dict:
    """Fetches a page from the official CLC26 conference website (clc-conference.eu).

    Use this to read the conference programme, individual talk details, speakers,
    tickets, venue, FAQ and other official information. Only pages on
    clc-conference.eu can be fetched.

    Useful pages:
      - "/" or "/index_en.php": overview (German / English)
      - "/programm.php": full conference programme with links to all talks
      - "/lecture.php?id=<id>": details of a single talk or workshop
      - "/konferenz.php": about the conference and venue
      - "/tickets_weiche.php": tickets and prices
      - "/faq.php": frequently asked questions

    Args:
        path_or_url: A path relative to https://clc-conference.eu/ or an absolute
            URL on clc-conference.eu.

    Returns:
        A dict with status, the fetched url, the readable page text and a list of
        links to other clc-conference.eu pages found on that page.
    """
    url = urljoin(CLC_BASE_URL, path_or_url.strip() or "/")
    if not _is_allowed(url):
        return {
            "status": "error",
            "error_message": f"Only pages on {CLC_BASE_URL} may be fetched, got: {url}",
        }

    request = Request(url, headers={"User-Agent": "clc26-adk-agent/0.1"})
    try:
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            final_url = response.geturl()
            charset = response.headers.get_content_charset() or "utf-8"
            html = response.read().decode(charset, errors="replace")
    except (HTTPError, URLError, TimeoutError) as error:
        return {"status": "error", "url": url, "error_message": str(error)}

    if not _is_allowed(final_url):
        return {"status": "error", "url": url, "error_message": f"Redirected off-site to {final_url}"}

    extractor = _PageExtractor(final_url)
    extractor.feed(html)
    text = extractor.text
    truncated = len(text) > MAX_TEXT_CHARS
    links = [{"url": link, "text": label} for link, label in list(extractor.links.items())[:MAX_LINKS]]

    return {
        "status": "success",
        "url": final_url,
        "text": text[:MAX_TEXT_CHARS],
        "truncated": truncated,
        "links": links,
    }
