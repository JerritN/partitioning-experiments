import java.nio.file.Files
import java.nio.file.Path
import org.yaml.snakeyaml.LoaderOptions
import org.yaml.snakeyaml.Yaml
import org.yaml.snakeyaml.constructor.SafeConstructor

class ExperimentFile {
    static Map read(Path path) {
        try {
            def settings = new LoaderOptions()
            settings.allowDuplicateKeys = false
            def yaml = new Yaml(new SafeConstructor(settings))
            def document = Files.newBufferedReader(path).withCloseable { reader -> yaml.load(reader) }
            if (!(document instanceof Map)) throw new IllegalArgumentException('Expected an experiment map')
            return document
        } catch (Exception e) {
            throw new IllegalArgumentException("Cannot load experiment ${path}: ${e.message}", e)
        }
    }
}
