#!/usr/bin/env bats
#
# tasks.md Task 24 / design.md section 7.2. tools/render-floors.sh rewrites each tool
# config's FLOORS:BEGIN/END block from floors.yml. The regression this file exists to
# pin: a fixture with TWO marked blocks in one file, because the first version of the
# renderer's regex used a DOTALL-greedy ".*" for the BEGIN line, which does not stop at
# its own end of line — it swallows forward past the intended END marker and locks onto
# whichever FLOORS:END is FURTHEST away, corrupting block 1 with block 2's content. A
# fixture with only one block per file could not have caught this.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  FIXTURE="$(mktemp -d)"
  mkdir -p "$FIXTURE/tools/lib" "$FIXTURE/examples/backend" "$FIXTURE/examples/frontend"
  cp "$REPO_ROOT/tools/render-floors.sh" "$FIXTURE/tools/render-floors.sh"
  cp "$REPO_ROOT/tools/lib/config.sh" "$FIXTURE/tools/lib/config.sh"
  chmod +x "$FIXTURE/tools/render-floors.sh"

  cat > "$FIXTURE/floors.yml" <<'EOF'
schema: 1
floors:
  backend.coverage.line:        { value: unset, direction: up,   tool: jacoco }
  backend.coverage.branch:      { value: unset, direction: up,   tool: jacoco }
  backend.mutation.score:       { value: unset, direction: up,   tool: pit }
  frontend.coverage.statements: { value: unset, direction: up,   tool: vitest }
  frontend.coverage.branches:   { value: unset, direction: up,   tool: vitest }
  frontend.coverage.functions:  { value: unset, direction: up,   tool: vitest }
  frontend.coverage.lines:      { value: unset, direction: up,   tool: vitest }
  frontend.mutation.score:      { value: unset, direction: up,   tool: stryker }
  frontend.bundle.total_kib:    { value: unset, direction: down, tool: bundle-check }
EOF

  # Two BEGIN/END blocks in ONE file — the exact shape that exposed the regression.
  cat > "$FIXTURE/examples/backend/pom.xml" <<'EOF'
<project>
  <properties>
    <!-- FLOORS:BEGIN backend.mutation.score -->
    <!-- placeholder comment -->
    <pit.mutationThreshold>0</pit.mutationThreshold>
    <!-- FLOORS:END -->
  </properties>
  <build>
    <plugins>
      <plugin>
        <configuration>
          <!-- FLOORS:BEGIN backend.coverage.line backend.coverage.branch -->
          <!-- placeholder comment -->
          <skip>true</skip>
          <rules/>
          <!-- FLOORS:END -->
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF

  cat > "$FIXTURE/examples/frontend/vitest.config.js" <<'EOF'
export default {
  test: {
    coverage: {
      // FLOORS:BEGIN frontend.coverage.*
      // placeholder comment
      thresholds: {},
      // FLOORS:END
    },
  },
};
EOF

  cat > "$FIXTURE/examples/frontend/stryker.config.mjs" <<'EOF'
export default {
  // FLOORS:BEGIN frontend.mutation.score
  // placeholder comment
  thresholds: { high: 95, low: 85, break: null },
  // FLOORS:END
};
EOF
}

teardown() {
  rm -rf "$FIXTURE"
}

@test "unset floors: every block renders and stays internally consistent" {
  cd "$FIXTURE"
  run bash tools/render-floors.sh
  [ "$status" -eq 0 ]

  # Each file has EXACTLY one BEGIN and one END per block — the regression produced two
  # comment blocks stacked between a single BEGIN/END pair, not a duplicated marker, so
  # this also greps for content duplication, not just marker count.
  [ "$(grep -c 'FLOORS:BEGIN backend.mutation.score' examples/backend/pom.xml)" -eq 1 ]
  [ "$(grep -c 'FLOORS:BEGIN backend.coverage.line' examples/backend/pom.xml)" -eq 1 ]
  [ "$(grep -c '<pit.mutationThreshold>' examples/backend/pom.xml)" -eq 1 ]
  [ "$(grep -cE '^ *<skip>(true|false)</skip>$' examples/backend/pom.xml)" -eq 1 ]
  [ "$(grep -c 'placeholder comment' examples/backend/pom.xml)" -eq 0 ]

  grep -q '<pit.mutationThreshold>0</pit.mutationThreshold>' examples/backend/pom.xml
  grep -q '<skip>true</skip>' examples/backend/pom.xml
  grep -q '<rules/>' examples/backend/pom.xml

  [ "$(grep -c 'thresholds: {}' examples/frontend/vitest.config.js)" -eq 1 ]
  [ "$(grep -c 'placeholder comment' examples/frontend/vitest.config.js)" -eq 0 ]

  grep -q 'thresholds: { high: 95, low: 85, break: null }' examples/frontend/stryker.config.mjs
  [ "$(grep -c 'placeholder comment' examples/frontend/stryker.config.mjs)" -eq 0 ]
}

@test "unset floors: rendering is idempotent" {
  cd "$FIXTURE"
  bash tools/render-floors.sh >/dev/null
  cp examples/backend/pom.xml /tmp/pom-after-1.$$.xml
  cp examples/frontend/vitest.config.js /tmp/vitest-after-1.$$.js
  cp examples/frontend/stryker.config.mjs /tmp/stryker-after-1.$$.mjs

  bash tools/render-floors.sh >/dev/null

  run diff -q /tmp/pom-after-1.$$.xml examples/backend/pom.xml
  [ "$status" -eq 0 ]
  run diff -q /tmp/vitest-after-1.$$.js examples/frontend/vitest.config.js
  [ "$status" -eq 0 ]
  run diff -q /tmp/stryker-after-1.$$.mjs examples/frontend/stryker.config.mjs
  [ "$status" -eq 0 ]

  rm -f /tmp/pom-after-1.$$.xml /tmp/vitest-after-1.$$.js /tmp/stryker-after-1.$$.mjs
}

@test "calibrated floors: JaCoCo, PIT, vitest and Stryker each render real values" {
  cd "$FIXTURE"
  cat > floors.yml <<'EOF'
schema: 1
floors:
  backend.coverage.line:        { value: 0.87, direction: up,   tool: jacoco }
  backend.coverage.branch:      { value: 0.79, direction: up,   tool: jacoco }
  backend.mutation.score:       { value: 0.86, direction: up,   tool: pit }
  frontend.coverage.statements: { value: 0.91, direction: up,   tool: vitest }
  frontend.coverage.branches:   { value: 0.84, direction: up,   tool: vitest }
  frontend.coverage.functions:  { value: 0.93, direction: up,   tool: vitest }
  frontend.coverage.lines:      { value: 0.92, direction: up,   tool: vitest }
  frontend.mutation.score:      { value: 0.9,  direction: up,   tool: stryker }
  frontend.bundle.total_kib:    { value: 400,  direction: down, tool: bundle-check }
EOF

  run bash tools/render-floors.sh
  [ "$status" -eq 0 ]

  grep -q '<skip>false</skip>' examples/backend/pom.xml
  grep -q '<minimum>0.87</minimum>' examples/backend/pom.xml
  grep -q '<minimum>0.79</minimum>' examples/backend/pom.xml
  grep -q '<pit.mutationThreshold>86</pit.mutationThreshold>' examples/backend/pom.xml

  grep -q 'thresholds: { statements: 91, branches: 84, functions: 93, lines: 92 }' examples/frontend/vitest.config.js

  grep -q 'thresholds: { high: 95, low: 85, break: 90 }' examples/frontend/stryker.config.mjs
}

@test "skips cleanly when no reference-stack tool config is present" {
  cd "$FIXTURE"
  rm -rf examples
  run bash tools/render-floors.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}
