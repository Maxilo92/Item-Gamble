# Item Gamble

Exchange items for coins, bet them on a target item and let the wheel of fortune decide. Needs Space Age, available for Factorio 2.0 and 2.1.

- **Item values:** every item gets a value computed from its recipes, raw materials and how much research it needs. Later items are worth more. Quality and freshness count. Works with items from other mods.
- **Coins:** like chips in a casino. Put items into the exchange slot and exchange them at 45 % of their value. Coins sit on your own account (not as items) and stay there when you close the window. There is no way back: coins are only good for spinning.
- **Chance:** you bet coins on a target item. Staking the full target value is a coin flip at 50 %, less stake means a lower chance. On average about a quarter of the exchanged value comes back as items.
- **Wheel:** an animated reel with near misses, fast and slow spins. The stake is always gone, a win pays the target.
- **Consolation prizes:** some of the losing fields hold a tenth or a hundredth of the stake in coins.
- **Free spins:** a miss can give a free spin (5 %). Like on a slot machine it replays the bet it was won with, multiplier included, for free. Free spins play automatically one after another.
- **Statistics:** coins staked, coins returned (prizes at their exchange value) and your best hit, right in the window.
- **Autospin:** the Auto button keeps spinning with your bet until you stop it or run out of coins.
- **Multiplier:** the green button next to Spin multiplies stake and prize of a spin (x1 up to x100). The chance stays the same.
- **Vanilla controls:** the window shows your inventory, items move with the usual clicks (left, right, shift, ctrl). Shift click puts a stack into the exchange slot.
- **Prize area:** grows with your wins and never keeps empty rows. "Take all" moves everything to your inventory, ctrl click takes one kind.
- **Open it** with ALT + G or the shortcut bar.

All numbers are mod settings: exchange rate, maximum and minimum chance, stake value factor, value per quality level, value for game progress, the share of consolation prizes and the free spin chance.

Chat commands: `/gamble-values [search]` writes all item values to `script-output/item-gamble/values.txt`, `/gamble-recalc` (admins) recalculates them.

Languages: English, German.

License: MIT

Source and bug reports: https://github.com/Maxilo92/Item-Gamble
