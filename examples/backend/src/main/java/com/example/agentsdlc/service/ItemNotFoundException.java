package com.example.agentsdlc.service;

public class ItemNotFoundException extends RuntimeException {

  public ItemNotFoundException(Long id) {
    super("item not found: " + id);
  }
}
