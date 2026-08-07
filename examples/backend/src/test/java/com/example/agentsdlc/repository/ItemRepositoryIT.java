package com.example.agentsdlc.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.agentsdlc.domain.Item;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * Gate 2 — integration tests against the REAL dependency, full migration chain applied
 * from scratch. Tagged `docker` so Failsafe (not Surefire) picks it up, and so it is
 * excluded entirely by `mvn verify -DskipITs` (the FAST-tier command) — this class needs
 * a real Postgres on localhost:5433, which `full-integration-tests` provides as a
 * service container and `fast-unit-tests` deliberately does not.
 *
 * NOT executed in a sandboxed dev session without Docker; wired to run for real the
 * moment a Postgres reachable at these coordinates exists — see .github/workflows/
 * pr-tests.yml's full-integration-tests job, which is exactly that environment.
 */
@Tag("docker")
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@ActiveProfiles("it")
class ItemRepositoryIT {

  @Autowired
  private ItemRepository repository;

  @Test
  void savesAndReloadsAnItemAgainstTheRealDatabase() {
    Item saved = repository.save(new Item("verify against postgres"));

    Item reloaded = repository.findById(saved.getId()).orElseThrow();

    assertThat(reloaded.getTitle()).isEqualTo("verify against postgres");
    assertThat(reloaded.isDone()).isFalse();
  }

  @Test
  void theMigrationChainAppliesCleanlyAndTheTableIsQueryable() {
    long before = repository.count();

    repository.save(new Item("migration smoke test"));

    assertThat(repository.count()).isEqualTo(before + 1);
  }
}
