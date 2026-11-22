package experiment

import groovy.transform.Canonical

@Canonical
class StageDefinition {
    final String tool
    final Map inputTemplate = [:]
    final List<String> vary = []
    final String id = null
}
