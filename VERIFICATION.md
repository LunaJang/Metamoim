# Verification — Metamoim vs Metabuli `64680ee4`

> 작성일: 2026-10-14 · Metamoim 커밋: (이 문서가 포함된 첫 커밋)
> · 기준: `/home/user1/src/Metabuli_work` @ `64680ee4` (브랜치 `master`)

Metamoim은 Metabuli의 read grouping 경로를 떼어낸 것이고, **같은 입력에 같은 산출물을 내야
한다**는 것이 설계 요구다. 그 요구는 "같은 코드를 같은 플래그로 컴파일한다"로 환원되며,
이 문서는 그 환원이 성립하는지에 대한 증거를 모아 둔 것이다.

**2026-10-14 갱신**: 브랜딩 정리로 21파일이 원본과 달라졌다. §1.2에 무엇이 어디까지
바뀌었는지 적었다. 로직은 손대지 않았고 결과 파일에는 닿지 않는다.

**2026-10-14 2차 갱신**: 9단계를 했다. fixture를 만들고 두 바이너리를 같은 데이터에
돌려 비교했다 — §7. 결과를 담는 파일은 **전부 바이트 동일**하다.

**2026-10-14 3차 갱신**: §7.4의 결함 네 건을 **고쳤다** — §8. 그리고 서열이 실제인
fixture를 하나 더 만들었다(§7.1b). 합성 서열로는 자동 cap이 한 번도 안 물렸는데, 실제
게놈에서는 기본값 그대로 물린다.

**2026-10-14 4차 갱신**: 다중 flush 라운드를 밟았고, 밟으려다 **star 모드가 `--max-ram`을
아예 무시하고 있었다**는 것을 찾아 고쳤다 — §9.

---

## 1. 소스 동일성

복사해 온 56파일 중 **35개는 원본과 바이트 동일**하고, **21개는 브랜딩만 바뀌었다**.

### 1.1 바이트 동일 (35파일)

| 대상 | 파일 수 | 결과 |
|---|---|---|
| `src/read-group/` | 3 (`GroupGenerator.{h,cpp}`, `GroupApplier.h`) | `cmp` 무차이 |
| `src/commons/` | 24 | `cmp` 무차이 |
| `src/util/` | 5 | `cmp` 무차이 |
| `src/workflow/` | 2 | `cmp` 무차이 |
| `src/uniref/UnirefTree.cpp` | 1 | `cmp` 무차이 |
| `src/version/Version.cpp` | 1 | `cmp` 무차이 |
| `lib/prodigal/` | 16 | `diff -r` 무차이 |
| `lib/fastq_utils/` | 6 | `diff -r` 무차이 |
| `lib/json/` | 3 | `diff -r` 무차이 |
| `lib/yxml/` | 3 | `diff -r` 무차이 |
| `LICENSE` | 1 | 무차이 (GPL-3.0) |

**`GroupGenerator.{h,cpp}`가 여기 있다는 것이 핵심이다.** 그룹을 만드는 4,511줄이 원본과
한 바이트도 다르지 않다.

`lib/prodigal`은 Metabuli 쪽에 `.DS_Store`가 하나 더 있어 16 대 17이다. 소스가 아니므로
복사하지 않았고 `diff`에서 제외했다.

### 1.2 브랜딩만 바뀐 파일 (21파일)

도구 이름이 `metamoim`인데 소스가 자기를 Metabuli라고 부르는 상태를 없앴다.
**로직은 한 줄도 손대지 않았다.**

| 종류 | 파일 수 | 변경 |
|---|---|---|
| 헤더 가드 | 17 | `METABULI_*` → `METAMOIM_*` (`#ifndef`/`#define`/`#endif` 3줄씩) |
| `src/commons/LocalParameters.h` | 1 | `DBTYPE_METABULI` → `DBTYPE_METAMOIM` (참조하는 곳 0군데인 상수) |
| `src/commons/LocalParameters.cpp:1059` | 1 | 파라미터 덤프 `"Metabuli Version (commit):"` → `"Metamoim Version (commit):"` |
| `src/commons/IndexCreator.cpp:1466` | 1 | `db.parameters`의 키 `Metabuli commit used to create the DB` → `Metamoim …` |
| `src/read-group/GroupApplier.cpp:179` | 1 | `"Original Metabuli result loaded from"` → `"Original classification result loaded from"` |

**이 다섯 가지가 산출물에 닿는 범위**

- 헤더 가드와 `DBTYPE_*`: 전처리기·컴파일 시간에만 존재한다. 바이너리 동작에 영향 0
- `LocalParameters.cpp`, `GroupApplier.cpp`: **stdout 로그 한 줄씩**. 결과 파일에 들어가지 않는다
- `IndexCreator.cpp`: `create-common-kmer-list`가 쓰는 `db.parameters`의 **한 줄**.
  이 키를 읽는 코드는 없다 — `common.cpp:136-158`의 파서가 보는 키는 `DB_name`,
  `Creation_date`, `Skip_redundancy`, `Syncmer`, `Syncmer_len`, `Kmer_format`,
  `Total_seq_length`, `Accession_level`뿐이다. 즉 기존 Metabuli DB를 Metamoim이 읽는 데도,
  그 반대에도 지장이 없다

**`groups` · `groupMap` · `groupRep` · `skipped_kmers` · `updated_classifications.tsv` ·
`updated_report.tsv`에는 영향이 없다.**

`src/workflow/groupApplication.cpp:28`의 `Metabuli-P`는 **바꾸지 않았다.** 분류기 이름이 아니라
`--min-vote-score` 기본값 0.15의 출처가 된 **논문 이름**이고, 그 문장은 왜 0.15를 일반값으로
쓸 수 없는지를 설명한다.

### 1.3 손으로 쓴 파일

| 파일 | Metabuli 대비 |
|---|---|
| `src/version/CMakeLists.txt`, `src/read-group/CMakeLists.txt` | **동일** (무수정 복사) |
| `src/commons/CMakeLists.txt` | `commons/Classifier.cpp`·`commons/Classifier.h` **2줄 삭제뿐**, 추가 0줄 |
| `src/{util,workflow,uniref}/CMakeLists.txt` | 신규 — 각각 9 / 2 / 2 파일 |
| `CMakeLists.txt` | 신규 — Metabuli 최상위의 동형. `project(metamoim)`, `data/` 없음 |
| `src/CMakeLists.txt` | 신규 — `benchmark` 제외, 타깃명 교체 |
| `src/metamoim.cpp` | 신규 — 진입점 |
| `src/MetamoimBase.cpp` | 신규 — 커맨드 8개를 `MetabuliBase.cpp`에서 줄 단위 추출 |
| `src/LocalCommandDeclarations.h` | 신규 — 진입 함수 8개 선언 |
| `.gitignore` | `util/metabuli` → `util/metamoim` **한 줄** |

## 2. 의존 고정

| 항목 | Metamoim | Metabuli | 일치 |
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
| Metamoim 고유 경고 | 88 |
| **`Metamoim \ Metabuli` (증가분)** | **0 — 공집합** (브랜딩 정리 뒤 재측정에서도 88건 그대로) |
| `Metabuli \ Metamoim` | 15 |

차집합 15건은 **전부 Metamoim이 복사하지 않은 9개 파일**에서 나온다:
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
| 빌드 | `[100%] Built target metamoim`, exit 0 |
| 에러 | 0 |
| 미정의 심볼 | 0 — `Classifier`·`UnirefDbCreator`·`UnirefClassifier` 제외가 링커에서 성립 |
| 되살린 TU | 없음 |
| 바이너리 | `build/src/metamoim` 26,923,384 B (Metabuli 27,627,960 B) |

## 5. Metabuli_work 무수정

작업 내내 Metabuli는 읽기만 했다. 경고 기준선을 잡는 빌드조차 소스 트리 밖에서 했다.

```
$ git -C /home/user1/src/Metabuli_work status --porcelain
(빈 출력)
```

## 6. 아직 증명되지 않은 것

- **실데이터 규모.** fixture는 2만 pair 미만이다. `--max-tmp-disk` fold 경로는 이 크기에서
  밟히지 않는다. 다중 flush는 §9에서 해결했다.
- **Metabuli에서 물려받은 결함들.** `research.md` §11의 항목은 그대로 복사됐다. 의도된 것이다 —
  동작이 달라지면 동일성 주장이 깨진다.

---

## 7. 실행 산출물 동일성 (2026-10-14)

### 7.1 fixture

`test/make_fixture.py`가 만든다. 시드 하나, 시계 없음, 외부 도구 없음 — 두 번 돌리면
바이트 동일한 입력이 나오고, 그래야 두 바이너리를 비교할 수 있다.

| | |
|---|---|
| assembly | 8개 (2속 × 2종 × 2균주), 각 30,000 bp |
| 공유 구조 | 전 assembly 공통 보존 블록 1,500 bp + 속별 블록 1,500 bp. 균주 간 0.5 % 치환 |
| taxonomy | `nodes.dmp` / `names.dmp` / `merged.dmp` / `taxid.map`. gtdb-taxdump처럼 assembly마다 고유 taxon |
| 리드 | 150 nt 페어드, 커버리지 15×, fragment 450±40, 오류율 0.2 % → **12,000 pair** |
| 분류 표 | Metabuli 열 순서. 55 %가 라벨을 갖고 그중 3 %는 틀린 종 — 투표가 할 일이 있게 |

경로 전체가 실제로 밟힌다: syncmer 추출 → 공통 k-mer 리스트 생성(종 2개 이상에 나타나는
k-mer만 남기는 merge) → 질의에서 공통 k-mer 제거(**132,435 match**) → 히스토그램·cap →
clique·star 간선 → 3단계 grouping(**clique 12 그룹 / star 234 그룹**, 12,000 read 전부 배치) →
가중 다수결 LCA 전파(**분류된 read 6,572 → 11,587**). κ̄ = 104.87, τ = 52로 논문의
58.4–113.0 범위 안이다.

자동 cap은 이 크기에서 k-mer를 100 % 남기므로, `--max-kmer-reads 30`을 준 arm을 하나 더
돌려 skip 경로를 밟힌다(1,715 k-mer skip, `skipped_kmers` 36 KB).

### 7.1b 서열이 실제인 fixture

`test/make_real_fixture.py`. 사람 코로나바이러스 레퍼런스 게놈 6개 —
`NC_045512.2`(SARS-CoV-2) · `NC_019843.3`(MERS-CoV) · `NC_002645.1`(229E) ·
`NC_006213.1`(OC43) · `NC_005831.2`(NL63) · `NC_006577.2`(HKU1) — 을 NCBI에서 받아
쓴다. **서로 다른 6개 종**이고 두 개 속(Alpha·Betacoronavirus)에 걸쳐 있다. taxonomy도
NCBI 것을 그 계보만 잘라 쓴다. 공통 k-mer 리스트가 찾는 상동성이 이 스크립트가 붙여 넣은
블록이 아니라 **게놈 자신의 보존 영역**(ORF1ab, RdRp)이라는 점이 합성 fixture와 다르다.

리드는 여전히 시뮬레이션이다 — 6종을 정답과 함께 덮는 공개 리드 세트가 없다. 바뀐 것은
서열이고, 조성·반복·종간 상동성이 사는 곳이 거기다.

| | 합성 | 실제 서열 |
|---|---|---|
| 게놈 | 8 assembly × 30,000 bp, 난수 | 6 레퍼런스, 27,317\~30,741 bp |
| 종 | 4 (가공) | **6 (NCBI 실제)** |
| read pair | 12,000 | 17,556 |
| 공통 k-mer | 붙여 넣은 블록에서 나온 것 | **508개, 전부 실제 보존 영역** |
| 질의에서 제거된 match | 132,435 | 23,058 |
| **자동 cap** | **한 개도 안 걸림** (100 % 유지) | **21개 skip** (99.9764 % 유지) |
| 그룹 | clique 12 / star 234 | clique 7 / star 341 |
| 전파 | 6,572 → 11,587 | 9,617 → 17,553 |

마지막 두 줄이 요점이다. 난수 서열에는 반복이 없어서 reads-per-k-mer cap이 기본값으로는
아무것도 안 자른다 — 합성 fixture에서 `--max-kmer-reads 30`을 손으로 줘야 했던 이유다.
실제 게놈에서는 그냥 물린다.

둘 다 같은 `run_equivalence.sh`로 돈다. fixture마다 `fixture.conf`가 taxonomy를 어떻게
주는지 적어 둔다 — 합성은 gtdb-taxdump를 흉내 내 `--gtdb 1`, 실제는 accession 표를 그대로
넘겨 `--gtdb 0`이라 names.dmp를 다시 쓰는 단계가 아예 없다.

### 7.2 비교 방법 — `test/run_equivalence.sh`

묻는 것이 둘이라 **두 바이너리를 각각 두 번씩** 돌린다.

1. metamoim이 **재현 가능한가** — 두 번 돌린 결과가 전부 같아야 한다
2. metabuli와 **일치하는가** — §8에서 일부러 다르게 쓰기로 한 네 파일을 뺀 전부

metabuli도 두 번 돌리는 이유는, 그쪽이 스스로 재현하지 못하는 파일이 있다는 사실을
가정하지 않고 **보여 주기** 위해서다.

비교 대상은 `metabuli` @ `64680ee4` (out-of-source `build_64680ee4`, `-DCMAKE_BUILD_TYPE=Release`,
Metamoim 빌드와 같은 설정: `HAVE_AVX2=0`, `-O3 -DNDEBUG`).

### 7.3 결과

**결과를 담는 파일 18개 전부 바이트 동일** (두 fixture 모두). 아래는 §8의 수정 **전** 표다.

| 파일 | metabuli ×2 | metamoim vs metabuli |
|---|---|---|
| `ckl/diffIdx` · `ckl/info` · `ckl/split` · `ckl/kmer_params` | stable | **동일** |
| `taxonomy/names.dmp` · `taxonomy/nodes.dmp` | stable | **동일** |
| `group/{groups,groupMap,skipped_kmers}` | stable | **동일** |
| `cap/{groups,groupMap,skipped_kmers}` | stable | **동일** |
| `easy/{groups,groupMap,skipped_kmers}` | stable | **동일** |
| `apply/{groupRep,updated_classifications.tsv,updated_report.tsv}` | stable | **동일** |
| `apply_easy/{groupRep,updated_classifications.tsv,updated_report.tsv}` | stable | **동일** |
| `ckl/taxID_list` | **UNSTABLE** | 같은 줄, 순서만 다름 |
| `taxonomy/taxid.accession2taxid` | **UNSTABLE** | 같은 줄, 순서만 다름 |
| `ckl/db.parameters` | **UNSTABLE** | `DB_name` + 도구 이름 키 |
| `ckl/taxonomyDB` | stable | 59 byte, **전부 구조체 패딩** |

### 7.4 동일하지 않은 네 파일, 하나씩 (고치기 전)

**`ckl/taxID_list`, `taxonomy/taxid.accession2taxid` — Metabuli 자신의 비결정성.**
같은 바이너리를 두 번 돌려도 줄 순서가 바뀐다. `--threads 1`로 내리면 두 파일 모두
재현된다. 원인은 `#pragma omp critical`에서 unordered 컨테이너로 병합하는 코드
(`accession2taxid.cpp:104-112`, `IndexCreator`의 `taxIdSet`)다. 줄의 **집합**은 항상 같다.

**`ckl/db.parameters` — `DB_name`이 난수다.**
`create_common_kmer_list.cpp:22-24`가 `srand(time(NULL))` 뒤 `rand()`로 DB 이름을 만든다.
실행마다 다르다. 두 번째 차이는 의도된 것으로, 도구 이름을 적는 키 한 줄이다:
`Metabuli commit used to create the DB` → `Metamoim …`. 이 키를 읽는 코드는 없다(§1.2).

**`ckl/taxonomyDB` — 초기화되지 않은 구조체 패딩 59 byte.**
`TaxonNode`는 `{int id; int taxId; int parentTaxId; size_t rankIdx; size_t nameIdx}`라
`rankIdx` 정렬 때문에 offset 12에 **4 byte 구멍**이 생기고, `serialize()`가 구조체를
`memcpy`로 그대로 써서 그 구멍의 쓰레기 값이 파일에 들어간다. `test/check_taxonomydb.py`가
다른 byte의 offset을 전부 구해 **모두 (offset − 블록시작) mod 32 ∈ [12,16)** 임을 확인한다 —
21개 노드 중 15개의 패딩이다. 의미를 담은 byte는 하나도 다르지 않다. 이것은 Metabuli에서
물려받은 결함이다. **§8에서 고쳤다.**

### 7.5 스레드·파티션 불변성 — `test/run_invariance.sh`

`--threads` {1, 4, 16} × `--partitions` {1, 4, 16}, 9칸.

| 모드 | 결과 |
|---|---|
| `grouping` (clique) | 9칸 전부 `groups`·`groupMap`·`skipped_kmers` 바이트 동일 |
| `easy-grouping` (star) | 9칸 전부 바이트 동일 |

### 7.6 재현

```sh
cd /home/user1/src/Metamoim
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build -j
cmake -S ~/src/Metabuli_work -B ~/src/Metabuli_work/build_64680ee4 -DCMAKE_BUILD_TYPE=Release
cmake --build ~/src/Metabuli_work/build_64680ee4 -j

python3 test/make_fixture.py test/fixture
./test/run_equivalence.sh
./test/run_invariance.sh
MODE=easy-grouping WORK=test/work_invariance_star ./test/run_invariance.sh
```

`test/fixture*/`와 `test/work*/`는 생성물이라 커밋하지 않는다. 생성기가 결정적이므로
어디서 돌려도 같은 입력이 나온다. 실제 서열 fixture는 첫 실행에서만 NCBI를 받고
`fixture_real/cache/`에 둔다.

서열이 실제인 쪽으로도 같은 것을 돌린다:

```sh
python3 test/make_real_fixture.py test/fixture_real
FIXTURE=$PWD/test/fixture_real WORK=$PWD/test/work_real ./test/run_equivalence.sh
./test/run_flush.sh
```

---

## 8. §7.4의 네 건을 고쳤다 (2026-10-14)

전부 Metamoim 쪽만 고쳤다. Metabuli_work는 여전히 한 바이트도 건드리지 않았다.

| 파일 | 원인 | 고친 곳 |
|---|---|---|
| `ckl/taxID_list` | `unordered_set`을 순회하며 그대로 씀 | `IndexCreator.cpp` 2군데 — `std::vector`로 옮겨 정렬 후 기록 |
| `taxonomy/taxid.accession2taxid` | `unordered_map`을 순회하며 그대로 씀 | `accession2taxid.cpp` — accession 기준 정렬 후 기록 |
| `ckl/db.parameters` | `DB_name`이 `srand(time(NULL))` + `rand()` | `create_common_kmer_list.cpp` — 기본값 `"common-kmer-list"`. 이름이 필요하면 `--db-name` |
| `ckl/taxonomyDB` | `TaxonNode`의 offset 12, 4 byte 패딩이 미초기화인 채 `memcpy`로 파일에 들어감 | `TaxonomyWrapper.cpp` `serialize()` — 노드 구역을 `memset`으로 0으로 깔고 다섯 필드를 `offsetof`로 제자리에 씀. **레이아웃 불변** — `unserialize()`가 버퍼를 `TaxonNode*`로 캐스팅해 읽기 때문 |

`TaxonNode`는 `lib/mmseqs` submodule 소유라 손대지 않았다. 구멍을 메우는 일은 그 구조체를
쓰는 쪽에서 한다.

### 8.1 고친 뒤

| | 합성 fixture | 실제 서열 fixture |
|---|---|---|
| metamoim ×2 | **25파일 전부 stable** | **24파일 전부 stable** |
| metabuli ×2 | `taxID_list`·`taxid.accession2taxid`·`db.parameters` unstable | `taxID_list`·`db.parameters`·**`taxonomyDB`** unstable |
| 결과 18파일 | 전부 바이트 동일 | 전부 바이트 동일 |
| 네 파일 | 같은 줄 정렬 / 이름 키 / 패딩 0 | 같음 |

실제 서열 fixture에서는 `taxonomyDB`가 metabuli 쪽에서 **실제로 unstable로 나왔다** —
패딩 쓰레기가 실행마다 달랐다. metamoim 쪽은 두 번 다 같다. 수정이 듣는다는 직접 증거다.

### 8.2 경고

수정 전후로 새 경고 0. 전수 재빌드해 `파일:줄:열: 메시지`를 비교하면 `IndexCreator.cpp`의
기존 경고 3건이 줄 번호만 14줄 밀렸고(두 군데에 7줄씩 추가), 줄 번호를 지우면
`Metamoim \ Metabuli`는 여전히 **공집합**이다.

처음 쓴 `taxonomyDB` 수정은 `TaxonNode`를 `memset`해서 `-Wclass-memaccess`를 새로
만들었다 — 사용자 제공 생성자가 있어 non-trivial이기 때문이다. `char *` 대상 `memset` +
`offsetof` 기록으로 바꿔 없앴다.

### 8.3 남은 비결정성

`db.parameters`의 `Creation_date`는 그대로 둔다. 날짜는 의도된 메타데이터지 결함이 아니다.
그래서 `db.parameters`는 날짜가 바뀌면 바이트가 바뀐다 — 비교에서 그 줄은 제외한다.

---

## 9. 다중 flush 라운드, 그리고 star가 `--max-ram`을 무시하던 문제 (2026-10-14)

### 9.1 왜 리드를 늘리는 걸로는 안 되는가

flush는 버퍼에 쌓인 pair 수가 `getRelationBudget(--max-ram)`에 닿을 때 일어난다. 기본
`--max-ram 128`에서 이 예산은 **3억 8천만 pair**다(이 장비 실측). fixture를 그 위로 올리려면:

| | pair/read | 2라운드에 필요한 read pair |
|---|---|---|
| clique | 35.7 | `--max-ram 2`로 낮추면 12만에서 101라운드 — 실측 확인 |
| star | 6.7 | 12만에서도 **1라운드**. `--max-ram 2`로도 1라운드 |

`--max-ram`은 flush 예산만이 아니라 질의 k-mer 버퍼도 정한다. `--max-ram 1`에서는
`Query k-mer number : 0`으로 추출 자체가 실패했다. 둔기다.

star를 다중 라운드로 보내려면 50만 pair 이상이 필요한데, 생성에도 실행에도 CI가
감당할 양이 아니다.

### 9.2 `--max-buffered-pairs`

flush 트리거만 직접 정하는 인자를 더했다. **0이 기본이고, 0이면 예전 그대로
`--max-ram`에서 유도한다** — 기존 경로는 한 바이트도 안 바뀐다.

같이 바꾼 것 하나: 스테이지 배치 크기를 `min(4096/shard, 예산/버퍼수)`로 제한했다. 배치가
가득 차야 drain이 돌고 예산은 drain 안에서만 확인되므로, 배치가 예산보다 크면 트리거에
영영 못 닿는다. 기본 예산에서는 `예산/버퍼수`가 백만 단위라 이 상한이 걸리지 않는다.

### 9.3 그래도 star는 1라운드였다 — 진짜 원인

예산을 200까지 낮춰도 star는 여전히 1라운드에 117,710 pair, 예산의 **588배**를 들고 있었다.

`GroupGenerator.cpp`의 k-mer 콜백은 star 분기 끝에서 **`return`** 했고, 예산 검사는 그
아래 clique 루프 다음에 있었다. 즉 **star 모드에서는 스캔 도중 flush가 한 번도 일어날 수
없었다.** `--max-ram`이 star에서 무시된다는 뜻이다 — CAMI2 strain-madness의 star 간선
7.87억 pair(60 B/pair면 약 47 GB)가 선언한 값과 무관하게 통째로 메모리에 머물렀다.

`return`을 `else`로 바꿔 두 분기가 같은 검사로 떨어지게 했다. 이것이
`Metabuli_work/research.md` §11-8("star의 다중 flush는 실행된 적이 없다")의 원인이고,
이제 닫혔다.

### 9.4 결과 — `test/run_flush.sh`

실제 서열 fixture(17,556 pair), 같은 입력을 예산만 바꿔 가며.

| 모드 | 예산 | 라운드 | `groups`·`groupMap`·`skipped_kmers` |
|---|---|---|---|
| grouping | 0 (유도) | 1 | 기준 |
| | 20,000 | 305 | 동일 |
| | 2,000 | 5,730 | 동일 |
| | 200 | 48,065 | 동일 |
| easy-grouping | 0 (유도) | 1 | 기준 |
| | 20,000 | 26 | 동일 |
| | 2,000 | 429 | 동일 |
| | 200 | **6,315** | 동일 |

가중치가 포화 덧셈이라 병합이 결합적이고, 따라서 라운드가 어떻게 쪼개지든 답이 같다 —
그 주장을 되풀이하는 대신 측정했다.

### 9.5 metabuli와의 관계

`run_equivalence.sh`는 기본 경로(`--max-buffered-pairs 0`)만 비교하므로 §7·§8의 결과는
그대로다 — 두 fixture 모두 결과 18파일 바이트 동일, 재확인했다. 새 경고도 0이다(줄 번호를
지운 경고 집합의 차집합이 공집합).

다만 §9.3의 수정은 **기본 경로의 동작도 바꾼다**: 큰 데이터에서 star는 이제 flush를 하고,
metabuli는 안 한다. 산출물은 같다(§9.4가 그것을 보인 것이다). 다른 것은 메모리 사용량이고,
metamoim 쪽이 선언한 `--max-ram`을 지킨다.

### 9.6 CI 비용

20코어 기준 실측:

| 단계 | 시간 |
|---|---|
| `run_equivalence.sh` (합성) | 42 s |
| `run_equivalence.sh` (실제 서열) | 43 s |
| `run_invariance.sh` × 2 | 25 s |
| `run_flush.sh` (기본 예산 `0 20000`) | 12 s |

fixture는 생성물이라 저장소에 안 들어간다(합성 8.7 MB, 실제 13 MB + NCBI 캐시).
`run_flush.sh`의 기본 sweep은 `0 20000`이다. `BUDGETS="0 20000 2000 200"`까지 돌리면
clique 48,065라운드 때문에 혼자 8분을 넘으니, 깊은 sweep은 수동이나 nightly로 돌린다.
