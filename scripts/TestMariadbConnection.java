import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;
import java.sql.SQLException;


public class TestMariadbConnection {
    public static void testConnection(String connectionUrl) throws ClassNotFoundException, SQLException {
        Class.forName("org.mariadb.jdbc.Driver");
        try (
        Connection con = DriverManager.getConnection(connectionUrl);
        Statement stmt = con.createStatement()
        ) {
            stmt.executeQuery("SELECT 1 FROM DUAL");
        }
    }

    public static void main(String[] args) {
        try {
            testConnection(args[0]);
        } catch (Throwable t) {
            if (args.length > 1 && "true".equals(args[1])) {
                t.printStackTrace();
            }
            System.exit(-1);
        }
    }
}
