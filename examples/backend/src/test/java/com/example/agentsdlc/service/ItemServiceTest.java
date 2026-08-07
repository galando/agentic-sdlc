package com.example.agentsdlc.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.example.agentsdlc.domain.Item;
import com.example.agentsdlc.repository.ItemRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

/** Gate 1 — unit tests, no database, no network: the repository is mocked out entirely. */
@ExtendWith(MockitoExtension.class)
class ItemServiceTest {

  @Mock
  private ItemRepository repository;

  @Test
  void createSavesAStrippedTitle() {
    ItemService service = new ItemService(repository);
    when(repository.save(any(Item.class))).thenAnswer(inv -> inv.getArgument(0));

    Item created = service.create("  buy milk  ");

    assertThat(created.getTitle()).isEqualTo("buy milk");
    assertThat(created.isDone()).isFalse();
    verify(repository).save(any(Item.class));
  }

  @Test
  void createRejectsABlankTitle() {
    ItemService service = new ItemService(repository);

    assertThatThrownBy(() -> service.create("   "))
        .isInstanceOf(IllegalArgumentException.class)
        .hasMessageContaining("blank");
  }

  @Test
  void findByIdThrowsWhenMissing() {
    ItemService service = new ItemService(repository);
    when(repository.findById(99L)).thenReturn(java.util.Optional.empty());

    assertThatThrownBy(() -> service.findById(99L))
        .isInstanceOf(ItemNotFoundException.class)
        .hasMessageContaining("99");
  }

  @Test
  void markDoneFlipsTheFlagAndSaves() {
    ItemService service = new ItemService(repository);
    Item existing = new Item("wash car");
    when(repository.findById(1L)).thenReturn(java.util.Optional.of(existing));
    when(repository.save(existing)).thenReturn(existing);

    Item result = service.markDone(1L);

    assertThat(result.isDone()).isTrue();
  }
}
