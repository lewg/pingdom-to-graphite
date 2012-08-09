Feature: Copy
  In order to populate graphite
  As a valid user of the Pingdom API
  I should be able to copy metrics from Pingdom

  Scenario: No argument
    When I run `pingdom-to-graphite`
    Then the output should contain:
    """
    Tasks:
    """

  Scenario: Initialize config file
    When I run `pingdom-to-graphite init -c configtest.json`
    Then the file "configtest.json" should contain "pingdom"

  
  Scenario: Initialize the checks data
    When I run `pingdom-to-graphite init_checks`
    Then the exit status should be 0
    Then the output should match /Added [\d]+ checks to/

  Scenario: Get a list of your checks
    When I run `pingdom-to-graphite list`
    Then the exit status should be 0
    Then the output should match /^.* \([\d]+\) - (up|down)/

  Scenario: Get some advice on API limits
    When I run `pingdom-to-graphite advice`
    Then the exit status should be 0
    Then the output should match /- WORKS$/

  Scenario: Get the list of pingdom probes
    When I run `pingdom-to-graphite probes`
    Then the exit status should be 0
    Then the output should match /^[A-Z]{2} - .*$/

  Scenario: Get the results for a specific probe
    When I run `pingdom-to-graphite results` with a valid check id
    Then the exit status should be 0
    Then the output should match /^[\d-]{10} [\d:]{8} (-|\+)[\d]{4}: (up|down) - [\d]+ms \(.*\)$/

  @graphite
  Scenario: Update the current checks without a state file
    Given A mock graphite server is running
    When I run `pingdom-to-graphite update -s teststate.json -c ../mockgraphite.json`
    Then the exit status should be 0
    Then graphite should have recieved results
    Then the file "teststate.json" should contain "latest_ts"
    Then the output should match /[\d]+ metrics sent to graphite for check [\d]+\./
    
  Scenario: Try to backfill a check that's never been updated
    When I run `pingdom-to-graphite backfill 1`
    Then the exit status should be 1
    Then the output should contain:
    """
    You can't backfill a check you've never run an update on.
    """

  @graphite @copystate
  Scenario: Backfill a specific check
    Given A mock graphite server is running
    When I run `pingdom-to-graphite backfill -c ../mockgraphite.json -s ../copiedstate.json -l 1` with a valid check id
    Then the exit status should be 0
    Then graphite should have recieved results
    Then the output should match /[\d]+ metrics sent to graphite for check [\d]+\./
