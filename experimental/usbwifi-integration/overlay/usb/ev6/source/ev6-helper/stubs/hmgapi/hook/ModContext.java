package hmgapi.hook;
public final class ModContext {
    public final String id = null;
    public java.lang.reflect.Member hook(ClassLoader cl, String point, MethodHook h) { return null; }
    public boolean enabled() { return true; }
    public void log(String s) {}
    public void error(String s, Throwable t) {}
    public boolean settingBoolean(String k, boolean d) { return d; }
    public int settingInt(String k, int d) { return d; }
}
