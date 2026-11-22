package experiment

import groovy.transform.Immutable

@Immutable
class DimensionReference {
    String dimension
    List<String> fields = []
}
