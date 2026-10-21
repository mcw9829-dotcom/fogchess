"""Bounded AI queue. Search runs in one isolated process, never in a room lock.

Only a copied game state and terrain cross the process boundary. The server
revalidates and applies the returned action to its authoritative state.
"""
import multiprocessing
import queue
import threading
import time
from concurrent.futures import ProcessPoolExecutor


MEMORY_KEYS = ('botmem', 'botscout', 'botenter', 'botscan', 'botswept', 'botscanned')


def decide(state, terrain, color, level):
    import bot
    import game_map
    import pieces

    game_map.apply_terrain(terrain, pieces, bot)
    if state.get('promote') and state['promote']['color'] == color:
        action = ('promote', None, 'R', None)
    else:
        choose = {'easy': bot.choose_action_easy, 'hard': bot.choose_action_hard}.get(level, bot.choose_action)
        action = choose(state, color)
    return {'action': action, 'memory': {k: state[k] for k in MEMORY_KEYS if k in state}}


class BotWorker:
    """One CPU worker keeps memory bounded; queued rooms take turns fairly.

    Callbacks execute in the dispatcher thread and acquire the server lock only
    for validation/application. Queue admission never waits for a free slot.
    """
    def __init__(self, capacity=32):
        self._queue = queue.Queue(maxsize=capacity)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name='fogchess-bot-dispatch', daemon=True)
        self._thread.start()

    def submit(self, state, terrain, color, level, minimum, current, complete):
        if self._stop.is_set():
            return False
        try:
            self._queue.put_nowait((state, terrain, color, level, minimum,
                                   time.monotonic(), current, complete))
            return True
        except queue.Full:
            return False

    def close(self):
        self._stop.set()
        self._thread.join()

    def _run(self):
        pool = None
        try:
            while not self._stop.is_set():
                try:
                    state, terrain, color, level, minimum, started, current, complete = self._queue.get(timeout=.1)
                except queue.Empty:
                    continue
                try:
                    if not current():
                        continue
                    if pool is None:
                        pool = ProcessPoolExecutor(max_workers=1, mp_context=multiprocessing.get_context('spawn'))
                    try:
                        result = pool.submit(decide, state, terrain, color, level).result()
                        error = None
                    except Exception as exc:
                        # A broken child can be replaced for the next request.
                        pool.shutdown(wait=True, cancel_futures=True)
                        pool = None
                        result, error = None, type(exc).__name__
                    if not self._stop.wait(max(0, minimum - (time.monotonic() - started))):
                        complete(result, error)
                except Exception as exc:
                    # A persistence/callback error must not kill the dispatcher.
                    print('[bot-worker]', type(exc).__name__, flush=True)
                finally:
                    self._queue.task_done()
        finally:
            if pool is not None:
                pool.shutdown(wait=True, cancel_futures=True)
