defmodule Verk.Supervisor do
  use Supervisor

  @doc false
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc false
  def init(_) do
    queues = Application.get_env(:verk, :queues, [])
    children = for { queue, size } <- queues, do: queue_child(queue, size)

    { :ok, redis_url } = Application.fetch_env(:verk, :redis_url)

    schedule_manager    = worker(Verk.ScheduleManager, [], id: :schedule_manager)
    verk_event_manager  = worker(GenEvent, [[name: Verk.EventManager]])
    queue_stats_watcher = worker(Verk.QueueStatsWatcher, [])
    redis               = worker(Redix, [redis_url, [name: Verk.Redis]])

    children = [redis, verk_event_manager, queue_stats_watcher, schedule_manager] ++ children
    supervise(children, strategy: :one_for_one)
  end

  @doc false
  def start_child(queue, size \\ 25) when is_atom(queue) and size > 0 do
    Supervisor.start_child(__MODULE__, queue_child(queue, size))
  end

  @doc false
  def stop_child(queue) when is_atom(queue) do
    supervisor_name = supervisor_name(queue)
    case Supervisor.terminate_child(__MODULE__, supervisor_name) do
      :ok -> Supervisor.delete_child(__MODULE__, supervisor_name)
      error = { :error, :not_found } -> error
    end
  end

  defp queue_child(queue, size) when is_atom(queue) do
    supervisor(Verk.Queue.Supervisor, [queue, size], id: supervisor_name(queue))
  end

  defp supervisor_name(queue) do
    String.to_atom("#{queue}.supervisor")
  end
end
