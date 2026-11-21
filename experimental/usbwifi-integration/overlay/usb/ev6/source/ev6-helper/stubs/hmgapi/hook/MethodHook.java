package hmgapi.hook;
public class MethodHook {
    public MethodHook() {}
    protected void afterHookedMethod(Param p) {}
    protected void beforeHookedMethod(Param p) {}
    public static final class Param {
        public final Object[] args = null;
        public final java.lang.reflect.Member method = null;
        public final Object thisObject = null;
        public Object getResult() { return null; }
        public void setResult(Object o) {}
    }
}
