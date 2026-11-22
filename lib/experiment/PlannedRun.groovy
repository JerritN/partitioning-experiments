package experiment

import groovy.transform.Canonical

@Canonical
class PlannedRun {
    final RunKey key
    final RunKey parentKey
    final Map inputs
    final Map choices
}
