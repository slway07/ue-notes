# ue-notes 작성 지침

## 시뮬레이션 필수

- **시간에 따라 상태가 변하는 주제는 정적 다이어그램만으로 끝내지 않는다.**
  실제로 상태가 진행되는 인터랙티브 시뮬레이션을 최소 1개 넣는다.
- 시뮬레이션은 `Viz.animate(view, step)`으로 `v.t`가 흐르고, 화면에 보일 때만 돈다.
  `Viz.view`만으로 그린 정적 그림이나 슬라이더만 있는 패널은 시뮬레이션이 아니다.
- 반드시 **재생 / 일시정지 / 리셋**이 있어야 한다.
  슬라이더·토글을 바꾸면 다음 프레임부터 결과에 반영되어야 한다.
- 시뮬레이션은 그 페이지의 핵심 개념을 직접 보여야 한다. 장식용 움직임은 넣지 않는다.
- 390px 폭에서 동작해야 하고, `prefers-reduced-motion: reduce`에서는 자동 재생하지 않고
  재생 버튼을 제공한다.
- 페이지를 추가·수정한 뒤 `tools/check-simulations.ps1`을 실행한다.
  검사에서 빠진 페이지가 나오면 배포하지 않는다.

## 예외

- 목차(`index.html`)와 순수 참조 표만 예외다.
- 예외인 페이지에는 "이 페이지는 참조 표라 시뮬레이션이 없다"를 한 줄로 적는다.

## 검사

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-simulations.ps1 -Root "D:\Work\Notes"
```

검사 스크립트는 각 `pages/*.html`에서 `Viz.animate(` 호출과 `data-sim` 마커를 확인한다.
