# ue-notes

언리얼 엔진을 공부하면서 만든 노트를 HTML 페이지로 모아둔 곳이다.
콘솔에 찍는 글자 대신 **눈으로 보는 것**이 목적이라, 다이어그램과 직접 만져보는
인터랙션 위주로 쓴다. 폰에서 읽는 것을 기준으로 만든다.

- 공개 주소: https://slway07.github.io/ue-notes/
- 다루는 범위: 엔진 기능 자체 (NavMesh, Collision, Animation Blueprint, Locomotion 등)

## 폴더

| 경로 | 내용 |
|---|---|
| `index.html` | 목차. 페이지 추가 시 스크립트가 갱신한다 |
| `pages/` | 페이지 하나당 HTML 파일 하나 |
| `assets/` | 공용 CSS / 이미지 |
| `tools/` | 검사·배포 스크립트 |

## 시뮬레이션

**시간에 따라 상태가 변하는 주제는 정적 다이어그램만으로 끝내지 않는다.**
`Viz.animate()`로 실제로 진행되는 인터랙티브 시뮬레이션을 최소 1개 넣는다.
재생·일시정지·리셋이 있어야 하고, 슬라이더를 바꾸면 다음 프레임부터 결과에 반영되어야 한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check-simulations.ps1 -Root "D:\Work\Notes"
```

## 배포

`tools/` 의 배포 스크립트를 통해서만 커밋·푸시한다.
배포 전에 검사 스크립트가 통과해야 하며, 하나라도 걸리면 배포가 중단된다.
