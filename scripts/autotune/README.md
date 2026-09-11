# ISUCON 自動改善ハーネス

`planner.sh` が未評価の候補を選び、`generator.sh` が変更を適用し、`evaluator.sh` が型チェック・コミット・リモートベンチ・結果保存を行う。

```bash
TARGET_SCORE=10000 CURRENT_SCORE=7477 ./scripts/autotune/run.sh
```

結果は `.autotune/results.tsv`、候補履歴は `.autotune/tried`、各ベンチの全文ログは `.autotune/*.log` に保存する。候補は1回だけ評価し、目標達成または候補枯渇で停止する。
