import java.nio.file.Files
import java.nio.file.Path

class FileUtils {
    /** Counts lines, including a final line without a newline. An empty file has zero rows. */
    static long countRows(Path file) {
        return Files.lines(file).withCloseable { lines -> lines.count() }
    }
}
