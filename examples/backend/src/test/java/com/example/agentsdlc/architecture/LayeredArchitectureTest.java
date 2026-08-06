package com.example.agentsdlc.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.classes;

import com.tngtech.archunit.core.domain.JavaClasses;
import com.tngtech.archunit.core.importer.ClassFileImporter;
import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.lang.ArchRule;
import com.tngtech.archunit.library.Architectures;
import com.tngtech.archunit.library.freeze.FreezingArchRule;
import org.junit.jupiter.api.Test;

/**
 * Gate 4 — architecture rules + freeze store. The boundary this example exists to
 * demonstrate: web -> service -> repository/domain, never the reverse, and the web
 * layer never reaches into the repository directly.
 *
 * Scoped to PRODUCTION classes only ({@link ImportOption.Predefined#DO_NOT_INCLUDE_TESTS}):
 * test helpers (a step-definition class, a MockMvc test) legitimately wire the
 * repository or service directly to set up fixtures, and that is not the boundary this
 * rule polices. Importing test classes here silently freezes THEM as "known
 * violations" on day one — exactly the failure this gate exists to catch, just aimed at
 * itself.
 *
 * Wrapped in {@link FreezingArchRule}: this repository ships with ZERO known
 * violations, so the frozen store (backend/archunit_store/) is committed empty. A NEW
 * violation fails the build; an EXISTING one (there are none yet) would be frozen and
 * shrink the store as it is fixed — never hand-edited to admit a new one. See
 * docs/QUALITY-GATES.md's ratchet policy.
 */
class LayeredArchitectureTest {

  @Test
  void layersRespectTheBoundary() {
    JavaClasses classes = new ClassFileImporter()
        .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
        .importPackages("com.example.agentsdlc");

    ArchRule layering = Architectures.layeredArchitecture()
        .consideringAllDependencies()
        .layer("Web").definedBy("com.example.agentsdlc.web..")
        .layer("Service").definedBy("com.example.agentsdlc.service..")
        .layer("Repository").definedBy("com.example.agentsdlc.repository..")
        .layer("Domain").definedBy("com.example.agentsdlc.domain..")
        .whereLayer("Web").mayNotBeAccessedByAnyLayer()
        .whereLayer("Service").mayOnlyBeAccessedByLayers("Web")
        .whereLayer("Repository").mayOnlyBeAccessedByLayers("Service")
        .whereLayer("Domain").mayOnlyBeAccessedByLayers("Web", "Service", "Repository");

    FreezingArchRule.freeze(layering).check(classes);
  }

  @Test
  void controllersLiveInTheWebPackage() {
    ArchRule rule = classes().that().haveSimpleNameEndingWith("Controller")
        .should().resideInAPackage("..web..")
        .andShould().beAnnotatedWith("org.springframework.web.bind.annotation.RestController");

    FreezingArchRule.freeze(rule)
        .check(new ClassFileImporter()
            .withImportOption(ImportOption.Predefined.DO_NOT_INCLUDE_TESTS)
            .importPackages("com.example.agentsdlc"));
  }
}
