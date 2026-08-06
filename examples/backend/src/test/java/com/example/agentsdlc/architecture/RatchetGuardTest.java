package com.example.agentsdlc.architecture;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

/**
 * Gate 9 — the backend half of the ratchet guard: a test whose only job is to read the
 * LIVE configs and fail if a floor was lowered, a threshold deleted, or a freeze store
 * removed. `fast-repo-hygiene`'s render-floors.sh diff (design.md section 7.5) catches a
 * hand-edit at pull-request time; this test is the one that survives even if that CI job
 * is ever deleted or bypassed, because it runs inside `mvn verify` itself.
 *
 * Never edit this test, floors.yml, or a FLOORS:BEGIN/END block to make a red run go
 * green — see docs/QUALITY-GATES.md's ratchet policy. That is an escalation, not a fix.
 */
class RatchetGuardTest {

  private static final Pattern FLOOR_ENTRY =
      Pattern.compile("^ {2}([a-z0-9_.]+):\\s*\\{\\s*value:\\s*([^,}]+)", Pattern.MULTILINE);

  private String floorsYml() throws IOException {
    Path repoRoot = findRepoRoot();
    return Files.readString(repoRoot.resolve("floors.yml"));
  }

  private String pomXml() throws IOException {
    Path repoRoot = findRepoRoot();
    return Files.readString(repoRoot.resolve("examples/backend/pom.xml"));
  }

  // Walks up from the working directory (Maven always runs `mvn` from backend/) to find
  // the repo root that holds floors.yml — no hardcoded absolute path, so this test works
  // from any checkout location.
  private Path findRepoRoot() {
    Path dir = Paths.get("").toAbsolutePath();
    while (dir != null) {
      if (Files.exists(dir.resolve("floors.yml"))) {
        return dir;
      }
      dir = dir.getParent();
    }
    throw new IllegalStateException("could not find floors.yml above " + Paths.get("").toAbsolutePath());
  }

  private String floorValue(String yml, String key) {
    Matcher m = FLOOR_ENTRY.matcher(yml);
    while (m.find()) {
      if (m.group(1).equals(key)) {
        return m.group(2).trim();
      }
    }
    // Calibrated (multi-line block) form: "  key:\n    value: X".
    Matcher block = Pattern.compile(
            "^ {2}" + Pattern.quote(key) + ":\\s*\\n\\s*value:\\s*([^\\n]+)",
            Pattern.MULTILINE)
        .matcher(yml);
    if (block.find()) {
      return block.group(1).trim();
    }
    throw new IllegalStateException("floors.yml has no entry for " + key);
  }

  @Test
  void jacocoRatchetAgreesWithFloorsYml() throws IOException {
    String yml = floorsYml();
    String pom = pomXml();
    String line = floorValue(yml, "backend.coverage.line");
    String branch = floorValue(yml, "backend.coverage.branch");

    if (line.equals("unset") || branch.equals("unset")) {
      assertThat(pom)
          .as("floors.yml has an unset backend coverage floor; pom.xml's jacoco:check must be skipped, not silently thresholded")
          .contains("<skip>true</skip>");
    } else {
      assertThat(pom)
          .as("floors.yml has calibrated backend coverage floors; pom.xml's jacoco:check must be armed, not skipped")
          .contains("<skip>false</skip>")
          .contains("<minimum>" + line + "</minimum>")
          .contains("<minimum>" + branch + "</minimum>");
    }
  }

  @Test
  void pitRatchetAgreesWithFloorsYml() throws IOException {
    String yml = floorsYml();
    String pom = pomXml();
    String score = floorValue(yml, "backend.mutation.score");

    if (score.equals("unset")) {
      assertThat(pom)
          .as("floors.yml has an unset mutation floor; pom.xml's pit.mutationThreshold must read as the tool's own uncalibrated value")
          .contains("<pit.mutationThreshold>0</pit.mutationThreshold>");
    } else {
      int expectedPercent = (int) Math.round(Double.parseDouble(score) * 100);
      assertThat(pom)
          .as("floors.yml has a calibrated mutation floor; pom.xml's pit.mutationThreshold must match it")
          .contains("<pit.mutationThreshold>" + expectedPercent + "</pit.mutationThreshold>");
    }
  }

  @Test
  void theArchitectureFreezeStoreHasNotBeenDeleted() {
    Path repoRoot = findRepoRoot();
    Path store = repoRoot.resolve("examples/backend/archunit_store");
    assertThat(Files.isDirectory(store))
        .as("the archunit_store/ freeze store must exist — see LayeredArchitectureTest and docs/QUALITY-GATES.md's ratchet policy on never removing a freeze store")
        .isTrue();
  }

  @Test
  void theMigrationDirectoryIsNeverEmptyAndCarriesNoDuplicateVersions() throws IOException {
    Path repoRoot = findRepoRoot();
    Path migrations = repoRoot.resolve("examples/backend/src/main/resources/db/migration");
    assertThat(Files.isDirectory(migrations)).isTrue();

    try (var files = Files.list(migrations)) {
      var versions = files
          .map(p -> p.getFileName().toString())
          .filter(name -> name.matches("V\\d+(\\.\\d+)*__.*\\.sql"))
          .map(name -> name.split("__")[0])
          .toList();
      assertThat(versions).as("no migrations found").isNotEmpty();
      assertThat(versions).as("duplicate Flyway version numbers").doesNotHaveDuplicates();
    }
  }
}
