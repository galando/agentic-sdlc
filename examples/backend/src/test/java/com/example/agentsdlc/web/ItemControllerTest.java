package com.example.agentsdlc.web;

import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.is;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.agentsdlc.repository.ItemRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Gate 1 — unit tests, no database, no network: runs against H2 in-memory
 * ("test" profile), never a real Postgres. The docker-tagged repository IT covers the
 * real dependency (gate 2).
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@AutoConfigureMockMvc
@ActiveProfiles("test")
class ItemControllerTest {

  @Autowired
  private MockMvc mockMvc;

  @Autowired
  private ItemRepository itemRepository;

  // Spring caches and reuses the application context (and its H2 instance) across test
  // classes that share an equivalent @SpringBootTest configuration — including the
  // Cucumber acceptance suite. Clearing here keeps this class's assertions independent
  // of execution order, same reasoning as ItemStepDefinitions#resetState.
  @BeforeEach
  void clearItems() {
    itemRepository.deleteAll();
  }

  @Test
  void createThenFetchRoundTrips() throws Exception {
    mockMvc.perform(post("/api/items")
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"title\":\"buy milk\"}"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.title", is("buy milk")))
        .andExpect(jsonPath("$.done", is(false)));

    mockMvc.perform(get("/api/items"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$[*].title", hasItem("buy milk")));
  }

  @Test
  void createRejectsABlankTitleWithBadRequest() throws Exception {
    mockMvc.perform(post("/api/items")
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"title\":\"\"}"))
        .andExpect(status().isBadRequest());
  }

  @Test
  void fetchingAMissingItemReturnsNotFound() throws Exception {
    mockMvc.perform(get("/api/items/999999"))
        .andExpect(status().isNotFound());
  }

  @Test
  void markDoneFlipsTheFlag() throws Exception {
    String body = mockMvc.perform(post("/api/items")
            .contentType(MediaType.APPLICATION_JSON)
            .content("{\"title\":\"wash car\"}"))
        .andReturn().getResponse().getContentAsString();
    Long id = Long.valueOf(body.replaceAll(".*\"id\":(\\d+).*", "$1"));

    mockMvc.perform(put("/api/items/" + id + "/done"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.done", is(true)));
  }
}
