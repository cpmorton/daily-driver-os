#!/usr/bin/env bats
# Contract: the documentation describes what the repository actually does.
# Everything this image adds must have a row in docs/PROVENANCE.md, every
# decision record must be indexed, and no documentation link may dangle.
#
# Run with: bats tests/contract/provenance_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
PROVENANCE="${REPO_ROOT}/docs/PROVENANCE.md"

# Print each item of the given kind, one per line, read from the repository.
items() {
	python3 - "${REPO_ROOT}" "$1" <<'PY'
import pathlib, re, sys

root, kind = pathlib.Path(sys.argv[1]), sys.argv[2]

def joined(path):
    # Fold shell line continuations so multi-line commands parse as one.
    return (root / path).read_text().replace("\\\n", " ")

if kind == "files":
    base = root / "custom/files"
    for p in sorted(base.rglob("*")):
        if (p.is_file() or p.is_symlink()) and p.relative_to(base).as_posix() != "README.md":
            print("/" + p.relative_to(base).as_posix())
elif kind == "packages":
    for script in ("build/70-daily-driver.sh", "build/75-claude.sh"):
        for m in re.finditer(r"^\s*dnf5 install -y (.+)$", joined(script), re.M):
            print(*m.group(1).split(), sep="\n")
elif kind == "units":
    text = joined("build/70-daily-driver.sh")
    for m in re.finditer(r"^\s*systemctl (?:--global )?(?:enable|disable|mask) ([^\n]+)$", text, re.M):
        print(*[u for u in m.group(1).split() if "." in u], sep="\n")
elif kind == "flatpaks":
    text = (root / "custom/flatpaks/daily.preinstall").read_text()
    print(*re.findall(r"^\[Flatpak Preinstall ([^\]]+)\]", text, re.M), sep="\n")
elif kind == "recipes":
    text = (root / "custom/ujust/daily-driver.just").read_text()
    print(*re.findall(r"^([a-z][a-z0-9-]*)(?=[ :])", text, re.M), sep="\n")
PY
}

# Fail listing every item of a kind that PROVENANCE.md doesn't mention in backticks.
assert_documented() {
	local kind=$1 missing=() item
	mapfile -t list < <(items "${kind}")
	[ "${#list[@]}" -gt 0 ] || { echo "found no ${kind} to check" >&2; return 1; }
	for item in "${list[@]}"; do
		grep -qF -- "\`${item}\`" "${PROVENANCE}" || missing+=("${item}")
	done
	if ((${#missing[@]})); then
		printf 'not in docs/PROVENANCE.md (%s): %s\n' "${kind}" "${missing[*]}" >&2
		return 1
	fi
}

@test "provenance: every file under custom/files is documented" {
	assert_documented files
}

@test "provenance: every package this repository installs is documented" {
	assert_documented packages
}

@test "provenance: every service this repository changes is documented" {
	assert_documented units
}

@test "provenance: every Flatpak in daily.preinstall is documented" {
	assert_documented flatpaks
}

@test "provenance: every daily-driver ujust recipe is documented" {
	assert_documented recipes
}

@test "decisions: every record is in the index, and numbers are unique" {
	cd "${REPO_ROOT}/docs/decisions"
	dupes="$(ls [0-9][0-9][0-9][0-9]-*.md | cut -c1-4 | uniq -d)"
	[ -z "${dupes}" ]
	for record in [0-9][0-9][0-9][0-9]-*.md; do
		grep -qF "(${record})" README.md || { echo "not indexed: ${record}" >&2; return 1; }
	done
}

@test "docs: every relative link resolves" {
	python3 - "${REPO_ROOT}" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
pages = [root / "README.md", root / "CLAUDE.md", *sorted((root / "docs").rglob("*.md"))]
broken = []
for page in pages:
    text = re.sub(r"```.*?```", "", page.read_text(), flags=re.S)  # skip code blocks
    for target in re.findall(r"\]\(([^)\s]+)\)", text):
        if re.match(r"[a-z]+:", target) or target.startswith("#"):
            continue
        path = target.split("#", 1)[0]
        if not (page.parent / path).exists():
            broken.append(f"{page.relative_to(root)} -> {target}")
if broken:
    sys.exit("broken links:\n" + "\n".join(broken))
PY
}

@test "docs: code comments point at decision records that exist" {
	run bash -c "grep -rhoE 'docs/decisions/[0-9]{4}-[a-z0-9-]+\.md' '${REPO_ROOT}/build' '${REPO_ROOT}/custom' | sort -u"
	for ref in ${output}; do
		[ -f "${REPO_ROOT}/${ref}" ] || { echo "missing: ${ref}" >&2; return 1; }
	done
}
