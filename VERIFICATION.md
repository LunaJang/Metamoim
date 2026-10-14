# Verification — Metamoum vs Metabuli `64680ee4`

> 작성일: 2026-10-14 · Metamoum 커밋: (이 문서가 포함된 첫 커밋)
> · 기준: `/home/user1/src/Metabuli_work` @ `64680ee4` (브랜치 `master`)

Metamoum은 Metabuli의 read grouping 경로를 떼어낸 것이고, **같은 입력에 같은 산출물을 내야
한다**는 것이 설계 요구다. 그 요구는 "같은 코드를 같은 플래그로 컴파일한다"로 환원되며,
이 문서는 그 환원이 성립하는지에 대한 증거를 모아 둔 것이다.

**이 문서가 증명하지 않는 것**: 실행 결과의 동일성. 두 바이너리를 같은 데이터에 돌려
`groups` / `groupMap` / `groupRep` / `updated_classifications.tsv`를 비교하는 일은
아직 하지 않았다(`plan.md` 9단계). 아래는 전부 **정적** 근거다.

---

## 1. 소스 동일성

복사해 온 파일은 전부 원본과 바이트 단위로 같아야 한다. `cmp` 전수 대조 결과:

| 대상 | 파일 수 | 결과 |
|---|---|---|
| `src/read-group/` | 4 | 무차이 |
| `src/commons/` | 38 | 무차이 |
| `src/util/` | 9 | 무차이 |
| `src/workflow/` | 2 | 무차이 |
| `src/uniref/` | 2 | 무차이 |
| `src/version/Version.cpp` | 1 | 무차이 |
| **소계** | **56** | **불일치 0** |
| `lib/prodigal/` | 16 | `diff -r` 무차이 |
| `lib/fastq_utils/` | 6 | `diff -r` 무차이 |
| `lib/json/` | 3 | `diff -r` 무차이 |
| `lib/yxml/` | 3 | `diff -r` 무차이 |
| `LICENSE` | 1 | 무차이 (GPL-3.0) |

`lib/prodigal`은 Metabuli 쪽에 `.DS_Store`가 하나 더 있어 16 대 17이다. 소스가 아니므로
복사하지 않았고 `diff`에서 제외했다.

### 1.1 손으로 쓴 파일 (여기만 Metabuli와 다르다)

| 파일 | Metabuli 대비 |
|---|---|
| `src/version/CMakeLists.txt` | **동일** (무수정 복사) |
| `src/read-group/CMakeLists.txt` | **동일** (무수정 복사) |
| `src/commons/CMakeLists.txt` | `commons/Classifier.cpp`·`commons/Classifier.h` **2줄 삭제뿐**, 추가 0줄 |
| `src/util/CMakeLists.txt` | 신규 — 9파일만 |
| `src/workflow/CMakeLists.txt` | 신규 — 2파일만 |
| `src/uniref/CMakeLists.txt` | 신규 — `UnirefTree.{h,cpp}`만 |
| `CMakeLists.txt` | 신규 — Metabuli 최상위의 동형. `project(metamoum)`, `data/` 없음 |
| `src/CMakeLists.txt` | 신규 — `benchmark` 제외, 타깃명 교체 |
| `src/metamoum.cpp` | 신규 — 진입점 |
| `src/MetamoumBase.cpp` | 신규 — 커맨드 8개를 `MetabuliBase.cpp`에서 줄 단위 추출 |
| `src/LocalCommandDeclarations.h` | 신규 — 진입 함수 8개 선언 |
| `.gitignore` | `util/metabuli` → `util/metamoum` **한 줄** |

**산출물에 닿는 코드(`src/read-group/`, `src/commons/`, `lib/`)에는 수정이 하나도 없다.**

## 2. 의존 고정

| 항목 | Metamoum | Metabuli | 일치 |
|---|---|---|---|
| `lib/mmseqs` (index SHA) | `62f8d3e17b429825695273e347775871339cda75` | 같음 | 예 |
| `lib/fasta_validator` (index SHA) | `ab9c05b81fc28c210dff5319e110b6aa8b81afa7` | 같음 | 예 |
| `lib/mmseqs` 원격 | `https://github.com/jaebeom-kim/MMseqs2.git` | 같음 | 예 |
| `lib/fasta_validator` 원격 | `https://github.com/jaebeom-kim/fasta_validator.git` | 같음 | 예 |

두 submodule 모두 **원래 URL에서 받았다.** 로컬 경로 대체 경로는 쓰지 않았다.

`62f8d3e1`은 MMseqs2 upstream의 최신이 아니라 `jaebeom-kim/MMseqs2` 포크의 master
(2025-05-28)다. Metabuli가 고정해 둔 값이며, 여기서 올리면 `Parameters`·`NcbiTaxonomy`
(`weightedMajorityLCA`)·`FileUtil`이 바뀌어 아래 §3의 근거가 무너진다. 업그레이드는
산출물 동일성이 실행으로 증명된 뒤 별건으로 한다.

## 3. 컴파일 동일성 — 경고 지문

경고는 컴파일러가 코드를 어떻게 읽었는지의 지문이다. 같은 코드를 같은 플래그로 컴파일하면
`파일:줄:열: 메시지 [-Wflag]`가 같아야 한다.

두 트리를 각각 `-DCMAKE_BUILD_TYPE=Release`로 전체 빌드해 고유 경고 집합을 비교했다
(Metabuli는 소스 트리를 건드리지 않도록 out-of-source로 빌드).

| | 건수 |
|---|---|
| Metabuli `64680ee4` 고유 경고 | 103 |
| Metamoum 고유 경고 | 88 |
| **`Metamoum \ Metabuli` (증가분)** | **0 — 공집합** |
| `Metabuli \ Metamoum` | 15 |

차집합 15건은 **전부 Metamoum이 복사하지 않은 9개 파일**에서 나온다:
`commons/Classifier.cpp`(4) · `uniref/UnirefDbCreator.{cpp,h}`(3) · `util/inspect_db.cpp`(2) ·
`util/printDeltaIdx.cpp`(2) · `util/createnewtaxalist.cpp`(1) · `util/expand_diffidx.cpp`(1) ·
`workflow/assign-uniref.cpp`(1) · `workflow/create-uniref-tree.cpp`(1).

즉 **공유 파일의 경고는 양쪽에서 완전히 일치한다.**

경고 88건은 전부 Metabuli에서 물려받은 것이고 이번 분리가 만든 것은 하나도 없다. 종류별:
`-Wc++17-extensions` 21 · `-Wreorder` 19 · `-Wunused-parameter` 12 · `-Wsign-compare` 11 ·
`-Wclass-memaccess` 9 · `-Wunused-variable` 6 · `-Wchar-subscripts` 4 · 기타 6.
고치는 것은 범위 밖이다 — 고치면 이 비교가 성립하지 않는다.

## 4. 빌드

| | |
|---|---|
| 빌드 | `[100%] Built target metamoum`, exit 0 |
| 에러 | 0 |
| 미정의 심볼 | 0 — `Classifier`·`UnirefDbCreator`·`UnirefClassifier` 제외가 링커에서 성립 |
| 되살린 TU | 없음 |
| 바이너리 | `build/src/metamoum` 26,923,384 B (Metabuli 27,627,960 B) |

## 5. Metabuli_work 무수정

작업 내내 Metabuli는 읽기만 했다. 경고 기준선을 잡는 빌드조차 소스 트리 밖에서 했다.

```
$ git -C /home/user1/src/Metabuli_work status --porcelain
(빈 출력)
```

## 6. 아직 증명되지 않은 것

- **실행 산출물의 동일성.** `plan.md` 9단계(검증 fixture 제작 + 바이트 비교)는 미착수다.
  현재 근거는 소스 `cmp`와 경고 지문 두 가지의 정적 근거뿐이다.
- **`easy-grouping`의 다중 flush 라운드.** Metabuli에서도 한 번도 밟힌 적이 없는 경로다
  (`Metabuli_work/research.md` §11-8).
- **Metabuli에서 물려받은 결함들.** `research.md` §11의 항목은 그대로 복사됐다. 의도된 것이다 —
  동작이 달라지면 동일성 주장이 깨진다.
