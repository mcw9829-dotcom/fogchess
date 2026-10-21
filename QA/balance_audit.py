"""Local bounded bot QA. Never connects to accounts, live servers or databases."""
import argparse
from collections import Counter
import json
from pathlib import Path
import random
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import bot
import pieces
import game_map


def play(seed, swapped, budget):
    random.seed(seed)
    terrain=game_map.generate_terrain(seed,symmetry='rotational')
    game_map.apply_terrain(terrain,pieces,bot)
    st=pieces.new_game()
    bot.setup_and_ready(st,'W'); bot.setup_and_ready(st,'B')
    st.update(phase='play',turn='W')
    levels={'W':'hard' if swapped else 'easy','B':'easy' if swapped else 'hard'}
    counts=Counter(); casualties=Counter(); first_lost=None
    decisions=[]; no_action=0; errors=[]
    for attempt in range(500):
        if st['phase']=='over': break
        side=st['turn']
        if st.get('promote'):
            ok,msg=pieces.apply_promote(st,side,'R')
            if not ok: errors.append({'turn':st['turnCount'],'error':msg}); break
            continue
        choose=bot.choose_action_hard if levels[side]=='hard' else bot.choose_action_easy
        start=time.perf_counter(); action=choose(st,side,budget=budget)
        decisions.append(time.perf_counter()-start)
        if not action:
            no_action+=1; pieces.time_out(st); continue
        kind,pid,r,c=action
        before={k:dict(v) for k,v in st['pieces'].items() if v['alive']}
        ok,msg={'move':pieces.apply_move,'fire':pieces.apply_fire,'barrage':pieces.apply_barrage,'scan':pieces.apply_scan}[kind](st,side,pid,r,c)
        if not ok:
            errors.append({'turn':st['turnCount'],'action':action,'error':msg}); break
        counts[before[pid]['t']+':'+kind]+=1
        for key,unit in before.items():
            if not st['pieces'][key]['alive']:
                casualties[unit['t']]+=1
                if first_lost is None: first_lost=unit['o']
    winner=st.get('winner') if st['phase']=='over' else None
    status='invalid_action' if errors else ('completed' if st['phase']=='over' else 'audit_cap')
    return {'seed':seed,'levels':levels,'status':status,'winner':winner,'turns':st['turnCount'],
            'actions':dict(counts),'casualties':dict(casualties),'first_loss_side':first_lost,
            'first_loss_won':winner==first_lost if winner in ('W','B') and first_lost else None,
            'no_action_timeouts':no_action,'decision_max_seconds':max(decisions,default=0),
            'errors':errors}


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--pairs',type=int,default=3)
    ap.add_argument('--budget',type=float,default=.05); ap.add_argument('--seed',type=int,default=20261021)
    ap.add_argument('--output',type=Path,default=Path('QA/balance-audit.json')); args=ap.parse_args()
    if args.pairs<1 or args.budget<=0: ap.error('pairs and budget must be positive')
    games=[]
    for n in range(args.pairs):
        for swapped in (False,True):
            game=play(args.seed+n,swapped,args.budget);games.append(game)
            print(json.dumps(game,ensure_ascii=True),flush=True)
    outcomes=Counter(g['winner'] or g['status'] for g in games)
    result={'kind':'bounded_local_bot_audit','budget_seconds':args.budget,
            'limitations':['Small bot-only sample; not human win-rate evidence.',
                           'Reduced search budget; not production difficulty strength.',
                           'audit_cap and invalid_action are never counted as draws.',
                           'Human confusion and abandonment require voluntary playtest feedback.'],
            'outcomes':dict(outcomes),'mean_turns':sum(g['turns'] for g in games)/len(games),'games':games}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    return int(any(g['errors'] for g in games))

if __name__=='__main__': raise SystemExit(main())
