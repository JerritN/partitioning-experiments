package experiment

import groovy.transform.Canonical

@Canonical
class PlannedStage {
    final String id
    final String tool
    final List<PlannedRun> runs
}
