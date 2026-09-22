package android.net;

import android.util.Pair;
import java.net.InetAddress;
import java.net.Inet6Address;
import java.net.UnknownHostException;

/**
 * @hide
 * KikiAOSP boot-classpath bridge; network implementation remains in Connectivity APEX. */
public final class NetworkUtils {
    private NetworkUtils() {}

    /** @hide */
    public static Pair<InetAddress, Integer> parseIpAndMask(String value) {
        return legacyParseIpAndMask(value);
    }

    /** @hide */
    @Deprecated
    public static Pair<InetAddress, Integer> legacyParseIpAndMask(String value) {
        try {
            String[] pieces = value.split("/", 2);
            int prefix = Integer.parseInt(pieces[1]);
            String address = pieces[0];
            if (address.isEmpty()) {
                byte[] bytes = new byte[16];
                bytes[15] = 1;
                return new Pair<>(Inet6Address.getByAddress("ip6-localhost", bytes, 0), prefix);
            }
            if (address.startsWith("[") && address.endsWith("]") && address.indexOf(':') >= 0) {
                address = address.substring(1, address.length() - 1);
            }
            return new Pair<>(InetAddress.getByName(address), prefix);
        } catch (Exception e) {
            throw new IllegalArgumentException("Invalid IP address and mask " + value, e);
        }
    }
}
