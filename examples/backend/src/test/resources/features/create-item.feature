Feature: Creating and completing an item
  # Gate 8 — executable acceptance specs. This is the agreed business rule stated in
  # language a non-engineer can read without opening a test file.

  Scenario: Adding a new item
    Given the item list is empty
    When I add an item titled "buy milk"
    Then the list contains an item titled "buy milk" that is not done

  Scenario: Completing an item
    Given I have added an item titled "wash the car"
    When I mark that item done
    Then the list contains an item titled "wash the car" that is done

  Scenario: A blank title is rejected
    When I try to add an item titled ""
    Then the request is rejected
