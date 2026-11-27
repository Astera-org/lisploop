"""The label-free rule on the 61-operator library, in bytes: classes of size N*-1 are used only
by unary operators at size N*, so they can be held as hashes (apply the unary operators at
once, keep the hash for dedupe).  Python bytes of plain search with sizes <= N*-2 as full
classes and size N*-1 as hashes (68.6 bytes each, m3_bytes_detail.log), over the 60 tasks.
Reads m3_lib61.json for the per-task counts of the filtered searches."""
import json
import multiprocessing as mp

from seqlib import OPNAMES, term_str
from q2tasks import review_tasks, training_tasks, my_tasks, gen_tasks
from mem61 import plain_pass
from memlib import deep_size

HASH_B = 68.6
TASKS = []


def job(ti):
    task = TASKS[ti]
    env, target = task['env'], task['target']
    pa = plain_pass(env, target, task['size'], asgo=True)
    ns = pa['hit_size']
    del pa
    if ns <= 2:
        return dict(name=task['name'], ns=ns, low_bytes=0, low_n=0)
    pg = plain_pass(env, target, ns - 1)            # stores sizes <= ns-2
    return dict(name=task['name'], ns=ns, low_bytes=deep_size([pg['seen'], pg['lev']]), low_n=pg['seen_n'])


def main():
    train = training_tasks(80, 100)
    rev = review_tasks(1)
    ex = {term_str(t['term']) for t in train} | {term_str(t['term']) for t in rev}
    mine = my_tasks(200, exclude=ex)
    ex |= {term_str(t['term']) for t in mine}
    extra = gen_tasks(40, 300, OPNAMES, prefix='X', exclude=ex)
    TASKS.extend(rev + mine + extra)
    with mp.get_context('fork').Pool(10) as pool:
        low = pool.map(job, range(len(TASKS)), chunksize=1)
    res = json.load(open('m3_lib61.json'))
    assert [r['name'] for r in res] == [l['name'] for l in low]
    P = sum(r['plain_bytes'] for r in res)
    lowb = sum(l['low_bytes'] for l in low)
    lown = sum(l['low_n'] for l in low)
    top = sum(r['plain_top'] for r in res)
    print('plain, 60 tasks: %d classes below N*, %.1f MB python' % (sum(r['plain_below'] for r in res), P / 1e6))
    print('   sizes <= N*-2: %d classes, %.1f MB; size N*-1: %d classes' % (lown, lowb / 1e6, top))
    ht = lowb + HASH_B * top
    print('   plain with size N*-1 as hashes: %.1f MB + %.1f MB of hashes = %.1f MB  (%.1fx less than plain)' %
          (lowb / 1e6, HASH_B * top / 1e6, ht / 1e6, P / ht))
    for cname in ('F-c', 'FL-c'):
        k = '2000|' + cname
        ff = sum(r['cfg'][k]['full_fused'] for r in res)
        hf = sum(r['cfg'][k]['hash_fused'] for r in res)
        by = sum(r['cfg'][k]['bytes'] for r in res)
        # full classes of the filtered search at sizes <= N-2 are plain's (same count); labels add
        # to each: take the filtered search's own mean bytes per class as the upper estimate
        per = by / max(1, sum(r['cfg'][k]['seen'] for r in res))
        est_lo = lowb + HASH_B * hf
        est_hi = per * ff + HASH_B * hf
        print('   %-5s: %.1f MB as run; with its size N-1 as hashes: %d full classes + %d hashes = %.1f to %.1f MB '
              '(%.1fx to %.1fx less than plain; %.1fx to %.1fx less than plain-with-hashes)' %
              (cname, by / 1e6, ff, hf, est_lo / 1e6, est_hi / 1e6, P / est_hi, P / est_lo, ht / est_hi, ht / est_lo))


if __name__ == '__main__':
    main()
