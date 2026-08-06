package com.example.agentsdlc.web;

import com.example.agentsdlc.domain.Item;
import jakarta.validation.constraints.NotBlank;

/** Request/response shapes for the item API — kept out of the domain and service layers. */
public final class ItemDtos {

  private ItemDtos() {
  }

  public record CreateItemRequest(@NotBlank String title) {
  }

  public record ItemResponse(Long id, String title, boolean done) {
    public static ItemResponse from(Item item) {
      return new ItemResponse(item.getId(), item.getTitle(), item.isDone());
    }
  }
}
