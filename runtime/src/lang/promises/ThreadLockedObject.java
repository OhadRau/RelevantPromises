package lang.promises;

public class ThreadLockedObject {
  private AsyncTask myTask;

  public ThreadLocalObject() {
    this.myTask = AsyncTask.currentTask();
  }

  public boolean access() {
    return this.myTask == AsyncTask.currentTask();
  }
}