-- Карты, убранные из случайных пулов, потому что другой мод даёт тот же эффект.
-- Ключ = убранная карта, значение = что остаётся вместо неё (и почему выбрана она).
-- Найдено сравнением английских описаний и config всех 3300 джокеров и ~1500 расходников (2026-10-25).
return {
	-- копирует крайнего правого джокера: три одинаковые редкие карты, оставлена Photocopy (Paperback)
	j_ortalab_right_hand = "j_paperback_photocopy",
	j_csau_greenneedle = "j_paperback_photocopy",
	-- $ за уничтоженную игральную карту: TOGA даёт $3 при обычной редкости, Bunco $2 при необычной
	j_bunc_nil_bill = "j_toga_diskcleanup",
	-- дикие карты дают +множ.: ExtraCredit +18 (обычный) против Bunco +9 (необычный)
	j_bunc_slothful = "j_ExtraCredit_pridefuljoker",
	-- повтор всех улучшенных карт: одинаковые карты SDM0 и Prism
	j_prism_exotic_card = "j_sdm_rock_n_roll",
	-- делит вероятности пополам: одинаковые Debian (TOGA) и Snake Eyes (Cryptposting)
	j_crp_snake_eyes = "j_toga_linux_debian",
	-- 1 к 2 создать планету при открытии бустера: одинаковые Kino и TOGA
	j_toga_mothernature = "j_kino_voyage_dans_le_lune",
	-- X множ., если в руке Две пары: Ortalab X3 против Cryptid X2.5
	j_cry_duos = "j_ortalab_shelter",
	-- каменные карты дают +множ.: Bunco +6 против Kino +5
	j_kino_rock = "j_bunc_mosaic",
	-- повтор карт масти, которая меняется каждый раунд
	j_csau_duane = "j_ExtraCredit_tuxedo",
	-- добор 3 карт после сброса: MoreFluff делает то же и после розыгрыша, при меньшей редкости
	j_kino_snakes_on_a_plane = "j_mf_snake",
	-- +2 слота расходников: у Kangaskhan есть тип Pokermon
	j_ExtraCredit_forklift = "j_poke_kangaskhan",
	-- +5 фишек за каждую карту с лицом в колоде
	j_kino_social_network = "j_csau_frens",
	-- дикие карты дают X множ.: Prism X1.75 против Kino X1.5
	j_kino_wizard_of_oz = "j_prism_vaquero",
	-- +1 слот карты в магазине
	j_toga_mswallet = "j_paperback_shopping_center",
	-- простой джокер +фишки: MoreFluff +40 против Ortalab +25
	j_ortalab_jester = "j_mf_jester",
}
