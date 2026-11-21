package hmgapi.hook;
public class ModEntry {
    public ModEntry() {}
    public void appLoaded(ModContext mod, LoadedApp app) {}
    public void onEnabled(ModContext mod, boolean enabled) {}
    public void onSettingsChanged(ModContext mod) {}
    public void zygoteInit(ModContext mod) {}
}
