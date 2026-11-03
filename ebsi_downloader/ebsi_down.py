"""
EBSi 기출/모의고사 자동 다운로더 (Playwright 사용, 크롬 확장 X)

사용법
  1) pip install -r requirements.txt
  2) python -m playwright install chromium
  3) python ebsi_down.py
     - 브라우저 창이 뜨면 직접 로그인
     - '기출문제' 페이지에서 학년/연도/월/과목 필터를 맞춘 뒤 터미널에서 Enter
     - 현재 목록의 문제/해설/정답/듣기 파일을 전부 받고, 다음 페이지로 넘어가며 반복

옵션
  --out 폴더        저장 위치 (기본: ./EBSi_모의고사)
  --types 문제,해설  받을 종류 필터 (기본: 전부)
  --no-next         다음 페이지 자동 이동 끔
  --delay 1.0       파일 사이 대기(초). 서버에 부담 안 주게 1초 이상 권장
"""

import argparse
import re
import sys
import time
from pathlib import Path
from urllib.parse import urlparse, unquote

from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout

START_URL = "https://www.ebsi.co.kr/ebs/xip/xipc/previousPaperList.ebs"
FILE_RE = re.compile(r"""https?://[^'"\s)]+?\.(?:pdf|hwp|hwpx|mp3|zip)""", re.I)
KIND_WORDS = ["문제", "해설", "정답", "듣기", "대본", "mp3", "pdf"]
BAD_CHARS = re.compile(r'[\\/:*?"<>|\r\n\t]+')


def safe(name: str) -> str:
    name = BAD_CHARS.sub("_", name).strip(" ._")
    return name[:150] or "file"


def collect_links(page):
    """현재 페이지(모든 frame)에서 다운로드 후보를 수집."""
    found = []
    for frame in page.frames:
        try:
            items = frame.evaluate(
                """() => {
                const out = [];
                const els = document.querySelectorAll('a, button, [onclick], [data-url], [data-href]');
                for (const el of els) {
                    const raw = [el.getAttribute('href'), el.getAttribute('onclick'),
                                 el.getAttribute('data-url'), el.getAttribute('data-href')]
                                 .filter(Boolean).join(' ');
                    // 목록 한 줄(행/카드)의 제목을 같이 가져와 파일명에 씀
                    const row = el.closest('li, tr, .board_qusesion, .board_list > div') || el.parentElement;
                    let title = '';
                    if (row) {
                        const t = row.querySelector('.tit, .title, strong, p, td');
                        title = (t ? t.innerText : row.innerText || '').trim().split('\\n')[0];
                    }
                    out.push({raw, text: (el.innerText || el.title || el.getAttribute('alt') || '').trim(), title});
                }
                return out;
            }"""
            )
        except Exception:
            continue
        for it in items:
            for url in FILE_RE.findall(it["raw"] or ""):
                found.append({"url": url, "text": it["text"], "title": it["title"]})
    # 중복 제거
    seen, uniq = set(), []
    for f in found:
        if f["url"] not in seen:
            seen.add(f["url"])
            uniq.append(f)
    return uniq


def click_candidates(page):
    """URL이 HTML에 안 드러나는 경우: '문제/해설/정답' 버튼을 직접 찾아 클릭용으로 반환."""
    loc = page.locator("a, button").filter(
        has_text=re.compile(r"^\s*(문제|해설|정답|듣기)\s*$")
    )
    return [loc.nth(i) for i in range(loc.count())]


def want(kind_filter, text, url):
    if not kind_filter:
        return True
    hay = f"{text} {url}"
    return any(k in hay for k in kind_filter)


def save_via_request(ctx, item, out_dir: Path, referer: str):
    url = item["url"]
    base = unquote(Path(urlparse(url).path).name)
    prefix = safe(item["title"]) if item["title"] else ""
    name = safe(f"{prefix}_{item['text']}_{base}" if prefix else base)
    dest = out_dir / name
    if dest.exists() and dest.stat().st_size > 0:
        print(f"  [건너뜀] 이미 있음: {name}")
        return
    r = ctx.request.get(url, headers={"Referer": referer}, timeout=120_000)
    if not r.ok:
        print(f"  [실패] {r.status} {url}")
        return
    body = r.body()
    if body[:15].lower().startswith(b"<!doctype") or body[:6].lower() == b"<html>":
        print(f"  [실패] 파일 대신 HTML이 옴(로그인/권한 확인): {url}")
        return
    dest.write_bytes(body)
    print(f"  [완료] {name} ({len(body)//1024} KB)")


def save_via_click(page, el, out_dir: Path):
    """버튼 클릭 → 다운로드 이벤트(또는 팝업 내 다운로드)를 잡아서 저장."""
    try:
        with page.expect_download(timeout=20_000) as dl_info:
            el.click()
        dl = dl_info.value
    except PWTimeout:
        print("  [실패] 클릭했지만 다운로드가 시작되지 않음")
        return
    dest = out_dir / safe(dl.suggested_filename)
    if dest.exists():
        print(f"  [건너뜀] 이미 있음: {dest.name}")
        dl.cancel()
        return
    dl.save_as(dest)
    print(f"  [완료] {dest.name}")


def go_next(page) -> bool:
    """페이지네이션 '다음' 또는 현재 번호+1 클릭."""
    cur = page.locator(".paging .on, .pagination .active, .paging strong").first
    try:
        n = int(cur.inner_text().strip())
        nxt = page.locator(".paging a, .pagination a").filter(has_text=re.compile(rf"^\s*{n+1}\s*$")).first
        if nxt.count():
            nxt.click()
            page.wait_for_load_state("networkidle")
            return True
    except Exception:
        pass
    nxt = page.locator("a.next, button.next, a:has-text('다음')").first
    if nxt.count() and nxt.is_enabled():
        nxt.click()
        page.wait_for_load_state("networkidle")
        return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="EBSi_모의고사")
    ap.add_argument("--types", default="", help="예: 문제,해설")
    ap.add_argument("--no-next", action="store_true")
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--profile", default=".ebsi_profile", help="로그인 유지용 브라우저 프로필 폴더")
    args = ap.parse_args()

    kinds = [k.strip() for k in args.types.split(",") if k.strip()]
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        # 프로필을 저장해두면 다음 실행 때 로그인 생략 가능
        ctx = p.chromium.launch_persistent_context(
            args.profile, headless=False, accept_downloads=True, viewport=None
        )
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.goto(START_URL)

        print("=" * 60)
        print("1) 브라우저에서 로그인하세요.")
        print("2) 기출문제 페이지에서 학년/연도/월/과목 필터를 맞추세요.")
        print("3) 준비되면 여기서 Enter (종료는 q + Enter)")
        print("=" * 60)

        while True:
            if input("> ").strip().lower() == "q":
                break
            page = ctx.pages[-1]  # 사용자가 새 탭에서 작업했을 수도 있음
            page_no = 1
            while True:
                page.wait_for_load_state("networkidle")
                items = [i for i in collect_links(page) if want(kinds, i["text"], i["url"])]
                print(f"\n[페이지 {page_no}] 파일 {len(items)}개 발견")

                if items:
                    for it in items:
                        save_via_request(ctx, it, out_dir, page.url)
                        time.sleep(args.delay)
                else:
                    btns = click_candidates(page)
                    btns = [b for b in btns if want(kinds, b.inner_text(), "")]
                    print(f"  링크가 숨겨져 있어 버튼 클릭 방식으로 시도 ({len(btns)}개)")
                    for b in btns:
                        save_via_click(page, b, out_dir)
                        time.sleep(args.delay)

                if args.no_next or not go_next(page):
                    break
                page_no += 1

            print(f"\n끝. 저장 위치: {out_dir.resolve()}")
            print("필터 바꿔서 더 받으려면 Enter, 종료는 q")

        ctx.close()


if __name__ == "__main__":
    sys.exit(main())
