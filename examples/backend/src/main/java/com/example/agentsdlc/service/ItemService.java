package com.example.agentsdlc.service;

import com.example.agentsdlc.domain.Item;
import com.example.agentsdlc.repository.ItemRepository;
import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * The service layer — the only thing the web layer may talk to (gate 4's architecture
 * boundary). Holds the one business rule this example carries: a title must not be blank.
 */
@Service
public class ItemService {

  private final ItemRepository repository;

  public ItemService(ItemRepository repository) {
    this.repository = repository;
  }

  @Transactional
  public Item create(String title) {
    if (title == null || title.isBlank()) {
      throw new IllegalArgumentException("title must not be blank");
    }
    return repository.save(new Item(title.strip()));
  }

  @Transactional(readOnly = true)
  public List<Item> findAll() {
    return repository.findAll();
  }

  @Transactional(readOnly = true)
  public Item findById(Long id) {
    return repository.findById(id).orElseThrow(() -> new ItemNotFoundException(id));
  }

  @Transactional
  public Item markDone(Long id) {
    Item item = findById(id);
    item.markDone();
    return repository.save(item);
  }
}
