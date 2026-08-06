package com.example.agentsdlc.acceptance;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.agentsdlc.repository.ItemRepository;
import com.example.agentsdlc.service.ItemService;
import io.cucumber.java.Before;
import io.cucumber.java.en.Given;
import io.cucumber.java.en.Then;
import io.cucumber.java.en.When;
import org.springframework.beans.factory.annotation.Autowired;

public class ItemStepDefinitions {

  @Autowired
  private ItemService itemService;

  @Autowired
  private ItemRepository itemRepository;

  private Long lastCreatedId;
  private RuntimeException lastError;

  // Spring caches and REUSES the application context (and therefore the same H2
  // instance) across test classes with an equivalent @SpringBootTest configuration —
  // ItemControllerTest included. Without clearing state here, "the item list is empty"
  // would pass or fail depending on which test class the runner happened to execute
  // first: exactly the "a nondeterministic test means some share of every other gate's
  // green runs was luck" failure mode gate 20 exists to catch. Each scenario gets a
  // clean table regardless of execution order.
  @Before
  public void resetState() {
    itemRepository.deleteAll();
    lastCreatedId = null;
    lastError = null;
  }

  @Given("the item list is empty")
  public void theItemListIsEmpty() {
    assertThat(itemService.findAll()).isEmpty();
  }

  @Given("I have added an item titled {string}")
  @When("I add an item titled {string}")
  public void iAddAnItemTitled(String title) {
    lastCreatedId = itemService.create(title).getId();
  }

  @When("I try to add an item titled {string}")
  public void iTryToAddAnItemTitled(String title) {
    try {
      itemService.create(title);
    } catch (RuntimeException e) {
      lastError = e;
    }
  }

  @When("I mark that item done")
  public void iMarkThatItemDone() {
    itemService.markDone(lastCreatedId);
  }

  @Then("the list contains an item titled {string} that is not done")
  public void theListContainsAnItemTitledThatIsNotDone(String title) {
    assertThat(itemService.findAll())
        .anySatisfy(item -> {
          assertThat(item.getTitle()).isEqualTo(title);
          assertThat(item.isDone()).isFalse();
        });
  }

  @Then("the list contains an item titled {string} that is done")
  public void theListContainsAnItemTitledThatIsDone(String title) {
    assertThat(itemService.findAll())
        .anySatisfy(item -> {
          assertThat(item.getTitle()).isEqualTo(title);
          assertThat(item.isDone()).isTrue();
        });
  }

  @Then("the request is rejected")
  public void theRequestIsRejected() {
    assertThat(lastError).isInstanceOf(IllegalArgumentException.class);
  }
}
