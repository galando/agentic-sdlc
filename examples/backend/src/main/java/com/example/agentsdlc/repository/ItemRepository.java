package com.example.agentsdlc.repository;

import com.example.agentsdlc.domain.Item;
import org.springframework.data.jpa.repository.JpaRepository;

/**
 * The repository layer. Nothing above the service layer may depend on this package
 * directly — see architecture.LayeredArchitectureTest (gate 4).
 */
public interface ItemRepository extends JpaRepository<Item, Long> {
}
