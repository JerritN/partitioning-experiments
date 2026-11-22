import groovy.transform.Canonical

@Canonical
class PlannedRun {
    final Map key
    final Map parentKey
    final Map inputs
    final Map choices
}
