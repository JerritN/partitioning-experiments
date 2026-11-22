package experiment

import groovy.transform.Canonical

@Canonical
class PlannedRun {
    final Object key
    final Object parentKey
    final Map inputs
    final Map choices
}
