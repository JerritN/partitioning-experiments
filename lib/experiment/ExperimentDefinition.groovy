package experiment

import groovy.transform.Canonical

@Canonical
class ExperimentDefinition {
    final String name
    final Map dimensions
    final List<StageDefinition> stages
    final List<Map> selections = [[:]]
}
