package com.example.agentsdlc.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * A single tracked item. The architecture boundary this example exists to demonstrate
 * (gate 4) is: web -> service -> repository/domain, never the reverse and never a
 * layer skipped — see architecture.LayeredArchitectureTest.
 */
@Entity
@Table(name = "items")
public class Item {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(nullable = false)
  private String title;

  @Column(nullable = false)
  private boolean done;

  protected Item() {
    // JPA
  }

  public Item(String title) {
    this.title = title;
    this.done = false;
  }

  public Long getId() {
    return id;
  }

  public String getTitle() {
    return title;
  }

  public boolean isDone() {
    return done;
  }

  public void markDone() {
    this.done = true;
  }
}
