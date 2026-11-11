"""Tools for researching the official QAware GmbH website."""

from __future__ import annotations

import re
from html.parser import HTMLParser
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urljoin, urlparse, urlunparse
from urllib.request import Request, urlopen

QAWARE_BASE_URL = "https://www.qaware.de/"
SITEMAP_URL = urljoin(QAWARE_BASE_URL, "/sitemap.xml")
ALLOWED_HOSTS = {"qaware.de", "www.qaware.de"}
MAX_TEXT_CHARS = 20_000
MAX_LINKS = 150
MAX_SITEMAP_PAGES = 300
TIMEOUT_SECONDS = 15
USER_AGENT = "qaware-adk-agent/0.1"


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
            if href and not href.startswith(("#", "mailto:", "tel:", "javascript:")):
                self._current_href = _strip_tracking(urljoin(self._base_url, href))
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


def _strip_tracking(url: str) -> str:
    """Removes the HubSpot ``hsLang`` query parameter and fragments to deduplicate links."""
    parsed = urlparse(url)
    query = "&".join(part for part in parsed.query.split("&") if part and not part.startswith("hsLang="))
    return urlunparse(parsed._replace(query=query, fragment=""))


def _get(url: str) -> tuple[str, str]:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.geturl(), response.read().decode(charset, errors="replace")


def fetch_qaware_page(path_or_url: str = "/") -> dict:
    """Fetches a page from the official QAware GmbH website (www.qaware.de).

    Use this to read QAware's service portfolio, expertise, project references,
    open job positions, career benefits, company information, events and news.
    Only pages on qaware.de can be fetched.

    Useful pages (German, English pages live below "/en/"):
      - "/leistungen": service portfolio and expertise
      - "/projekte": project references and case studies
      - "/karriere": careers overview
      - "/karriere/professionals": open positions for professionals
      - "/karriere/studierende": positions for students, internships and theses
      - "/karriere/benefits", "/karriere/entwicklung", "/karriere/arbeitsplatz": benefits and development
      - "/unternehmen/ueber-uns", "/unternehmen/team", "/unternehmen/partner/": company, locations, partners
      - "/events", "/news", "/whitepaper", "/podcast": events, news and publications
      - "/kontakt": contact information

    Args:
        path_or_url: A path relative to https://www.qaware.de/ or an absolute URL
            on qaware.de.

    Returns:
        A dict with status, the fetched url, the readable page text and a list of
        links to other qaware.de pages found on that page.
    """
    url = urljoin(QAWARE_BASE_URL, path_or_url.strip() or "/")
    if not _is_allowed(url):
        return {
            "status": "error",
            "error_message": f"Only pages on {QAWARE_BASE_URL} may be fetched, got: {url}",
        }

    try:
        final_url, html = _get(url)
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


def list_qaware_pages(section: str = "") -> dict:
    """Lists pages of the official QAware website from its sitemap, optionally filtered by section.

    Use this to discover all currently published pages of a section, e.g. every
    open job position ("karriere"), every project reference ("projekte") or all
    events ("events"), before reading individual pages with `fetch_qaware_page`.

    Args:
        section: Optional path prefix to filter by, e.g. "karriere",
            "karriere/professionals", "karriere/studierende", "projekte",
            "leistungen", "events", "news", "whitepaper" or "en". An empty value
            lists all pages except blog posts.

    Returns:
        A dict with status, the section filter and the matching page URLs.
    """
    try:
        _, sitemap = _get(SITEMAP_URL)
    except (HTTPError, URLError, TimeoutError) as error:
        return {"status": "error", "url": SITEMAP_URL, "error_message": str(error)}

    prefix = "/" + section.strip().strip("/")
    pages: list[str] = []
    for loc in re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", sitemap):
        path = unquote(urlparse(loc).path)
        if not _is_allowed(loc) or "/hubfs/" in path:
            continue
        if prefix != "/" and not (path == prefix or path.startswith(prefix + "/")):
            continue
        if prefix == "/" and "/blog/" in path:
            continue
        if loc not in pages:
            pages.append(loc)

    return {
        "status": "success",
        "section": section,
        "count": len(pages),
        "pages": pages[:MAX_SITEMAP_PAGES],
        "truncated": len(pages) > MAX_SITEMAP_PAGES,
    }
