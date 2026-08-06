package com.example.agentsdlc.web;

import com.example.agentsdlc.service.ItemService;
import com.example.agentsdlc.web.ItemDtos.CreateItemRequest;
import com.example.agentsdlc.web.ItemDtos.ItemResponse;
import jakarta.validation.Valid;
import java.net.URI;
import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The web layer. Talks to {@link ItemService} only — never to the repository directly.
 * See architecture.LayeredArchitectureTest (gate 4).
 */
@RestController
@RequestMapping("/api/items")
public class ItemController {

  private final ItemService service;

  public ItemController(ItemService service) {
    this.service = service;
  }

  @PostMapping
  public ResponseEntity<ItemResponse> create(@Valid @RequestBody CreateItemRequest request) {
    var created = service.create(request.title());
    return ResponseEntity.created(URI.create("/api/items/" + created.getId()))
        .body(ItemResponse.from(created));
  }

  @GetMapping
  public List<ItemResponse> findAll() {
    return service.findAll().stream().map(ItemResponse::from).toList();
  }

  @GetMapping("/{id}")
  public ItemResponse findById(@PathVariable Long id) {
    return ItemResponse.from(service.findById(id));
  }

  @PutMapping("/{id}/done")
  public ItemResponse markDone(@PathVariable Long id) {
    return ItemResponse.from(service.markDone(id));
  }
}
