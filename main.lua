--[[
	ucac можно скачать здесь
	https://drive.google.com/drive/folders/1k3ecxnD937R0z-uibR33XfHFDtfAa-Ma

	инфа по фаормату, в котором хранится ucac
	https://www.simfov.ru/catalogs/ucac2/readme.txt

	tycho можно скачать здесь
	https://www.kaggle.com/datasets/konivat/tycho-star-catalog?resource=download
]]

--------------------------------------------------------------------------------
-- Подключаем библиотеки
--------------------------------------------------------------------------------

local ffi = require("ffi")  -- для взаимодействия с кодом на си
local util = require("util")  -- вспомогательные функции из файла util.lua

-- вспомогательные функции и структуры из файлов help.c/help.h
-- необходимо скомпилировать такой командой:
-- gcc -fPIC -shared -o libhelp.so help.c
local help_lib_name = ffi.os == "Windows" and "libhelp" or "help"
local help = ffi.load(help_lib_name)
ffi.cdef(util.read_file("help.h"))

--------------------------------------------------------------------------------
-- Читаем ucac
--------------------------------------------------------------------------------

-- структура типа ucac_star объявлена в help.h

-- заносим размер структуры ucac_star в переменную
local ucac_star_size = ffi.sizeof("ucac_star")

-- определяем размер всех файлов ucac чтобы заранее выделить под них место
-- в оперативной памяти
print("counting ucac size")
local ucac_size = 0
for i = 1, 288 do
	local file_name = ("ucac2/z%03d"):format(i)
	ucac_size = ucac_size + util.get_file_size(file_name)
end
print("ucac size (bytes):", ucac_size)  -- 2126545124

-- количество звёзд в ucac
local ucac_count = ucac_size / ucac_star_size
print("ucac size (stars):", ucac_count)  -- 48330571

-- выделяем массив из ucac_count структур типа ucac_star
local ucac = ffi.new("ucac_star[?]", ucac_count)

-- байтовый указатель на тот же массив чтобы последовательно копировать данные
-- перемещая указатель после каждого копирования на длину скопированных данных
local ucac_ptr = ffi.cast("uint8_t*", ucac)

print("reading ucac")
for i = 1, 288 do
	local file_name = ("ucac2/z%03d"):format(i)
	local content = util.read_file(file_name)

	ffi.copy(ucac_ptr, content, #content)
	ucac_ptr = ucac_ptr + #content
end

-- сортируем массив ucac по возрастанию ucac_star.de
print("sorting ucac")
help.sort_ucac(ucac, ucac_count, ucac_star_size)

-- минимальное и максимальное значения de
print("min ucac de:", ucac[0].de)
print("max ucac de:", ucac[ucac_count - 1].de)

--------------------------------------------------------------------------------
-- Читаем tycho
--------------------------------------------------------------------------------

-- структура типа tycho_star объявлена в help.h

-- заносим размер структуры ucac_star в переменную
local tycho_star_size = ffi.sizeof("tycho_star")

-- если есть tycho в бинарном формате, используем его
-- иначе читаем его из csv и сохраняем в bin
-- чтобы в следующие запуски tycho читалось быстрее

local tycho, tycho_count

local file = io.open("tycho.bin", "rb")  -- открываем для чтения
if file then
	print("reading tycho from bin")
	local data = file:read("*a")
	file:close()
	tycho_count = #data / tycho_star_size
	tycho = ffi.new("tycho_star[?]", tycho_count)
	ffi.copy(tycho, data, #data)
else
	-- читаем текстовый tycho-voidmain.csv в массив типа tycho_star
	-- значения для полей структуры берём из соотв. столбцов, указанных ниже
	print("reading tycho from csv")
	tycho, tycho_count = util.read_file_csv("tycho-voidmain.csv", "tycho_star", {
		mRAdeg = "ra",
		mDEdeg = "de",
		BTmag = "bmag",
		VTmag = "vmag",
	})
	print("writing tycho to bin")
	file = assert(io.open("tycho.bin", "wb"))  -- открываем для записи
	file:write(ffi.string(tycho, tycho_count * tycho_star_size))
	file:close()
end

-- размер получившегося массива в байтах
print("tycho size (bytes):", tycho_count * tycho_star_size)

-- количество звёзд в tycho
print("tycho size (stars):", tycho_count)

-- преобразуем поля ra и de в tycho_star из градусов в миллисекунды
print("converting tycho values")
for i = 0, tycho_count - 1 do
	local star = tycho[i]

	star.ra = 3600000 * star.ra
	star.de = 3600000 * star.de
end

-- сортируем массив tycho по возрастанию tycho_star.de
print("sorting tycho")
help.sort_tycho(tycho, tycho_count, tycho_star_size)

-- минимальное и максимальное значения de
print("min tycho de:", tycho[0].de)
print("max tycho de:", tycho[tycho_count - 1].de)

--------------------------------------------------------------------------------
-- Поиск пар звёзд
--------------------------------------------------------------------------------

-- значения mag в двух каталогах приведены в разных размерностях
-- в вычислениях будем приводить их к размерности [0.001 mag]
-- tycho mag даны в [mag], * 1000 [0.001 mag]
-- ucac mag даны в [0.01 mag], * 10 [0.001 mag]

-- так как массивы звёзд отсортированы, то это позволяет нам
-- быстро найти пары звёзд
-- подробнее алгоритм описан в util.lua

print("finding pairs")
local _pairs = util.find_pairs(ucac, tycho, ucac_count, tycho_count, function(u, t)
	local delta = t.de - u.de

	-- если de отличаются более чем на 1000мс, возвращаем "в какую сторону отличаются"
	-- важен только знак
	if math.abs(delta) > 1000 then
		return delta
	end

	delta = t.ra - u.ra

	-- если ra отличаются более чем на 1000мс, двигаемся по "основному" массиву
	if math.abs(delta) > 1000 then
		return
	end

	-- не забываем привести mag к одной размерности [0.001 mag]
	delta = t.vmag * 1000 - u.mag * 10

	-- если ra отличаются более чем на 1 mag, двигаемся по "основному" массиву
	if math.abs(delta) > 1000 then
		return
	end

	-- все уловия выполнились, значит считаем что это одна и та же звезда
	return 0
end)

-- выводим число найденных пар
local N = #_pairs
print("pairs:", N)

-- выводим несколько пар
for i = 1, 1 do
	print("-- Pair " .. i)
	local pair = _pairs[i]
	local ucac_star = ucac[pair[1]]
	local tycho_star = tycho[pair[2]]
	print("ucac: ")
	print("  de: " .. ucac_star.de)
	print("  ra: " .. ucac_star.ra)
	print("  mag: " .. ucac_star.mag * 0.01)
	print("tycho: ")
	print("  de: " .. tycho_star.de)
	print("  ra: " .. tycho_star.ra)
	print("  vmag: " .. tycho_star.vmag)
	print("  bmag: " .. tycho_star.bmag)
end

--------------------------------------------------------------------------------
-- Вычисление ошибок
--------------------------------------------------------------------------------

-- так как в массиве пар лежат только индексы звёзд,
-- для удобства вытащим значения поближе
-- ra и de переименуем в alpha и delta и переведём в градусы
-- магнитуды переведём в mag
for i = 1, N do
	local pair = _pairs[i]
	local ucac_star = ucac[pair[1]]
	local tycho_star = tycho[pair[2]]

	pair.alpha_u = ucac_star.ra / 3600000
	pair.delta_u = ucac_star.de / 3600000
	pair.mag_u = ucac_star.mag * 0.01

	pair.alpha_t = tycho_star.ra / 3600000
	pair.delta_t = tycho_star.de / 3600000
	pair.vmag_t = tycho_star.vmag
	pair.bmag_t = tycho_star.bmag
end

--------------------------------------------------------------------------------
-- первые и вторые дельты
--------------------------------------------------------------------------------

-- считаем первые дельты
for i = 1, N do
	local pair = _pairs[i]
	pair.d_alpha_1 = pair.alpha_t - pair.alpha_u
	pair.d_delta_1 = pair.delta_t - pair.delta_u
end

-- считаем средние ошибки
local d_A = 0
local d_D = 0
for i = 1, N do
	local pair = _pairs[i]
	d_A = d_A + pair.d_alpha_1
	d_D = d_D + pair.d_delta_1
end
d_A = d_A / N
d_D = d_D / N

-- выводим средние ошибки
print("d_A:", d_A)
print("d_D:", d_D)

-- считаем вторые дельты
for i = 1, N do
	local pair = _pairs[i]
	pair.d_alpha_2 = pair.d_alpha_1 - d_A
	pair.d_delta_2 = pair.d_delta_1 - d_D
end

--------------------------------------------------------------------------------
-- деление по alpha, третьи дельты
--------------------------------------------------------------------------------

-- разделяем пары по alpla в 360 полос шириной 1 градус
-- [0; 1), [1; 2), ..., [359, 360)
local bands_alpha = {}
for i = 1, 360 do
	bands_alpha[i] = {}  -- создаём пустые полосы
end

for i = 1, N do
	local pair = _pairs[i]

	-- определяем номер полосы
	-- находим остаток от деления alpha на 360
	-- чтобы быть уверенным, что alpha в [0, 360)
	-- округляем вниз, получаем целые числа от 0 до 359
	-- прибавляем 1 так как полосы от 1 до 360
	local j = math.floor(pair.alpha_t % 360) + 1

	-- добавляем пару в полосу
	table.insert(bands_alpha[j], pair)
end

-- число пар в перой полосе
print("bands_alpha[1]", #bands_alpha[1])

-- для каждой полосы считаем ошибки
for j = 1, 360 do
	local band = bands_alpha[j]
	local M = #band  -- число пар в полосе

	-- считаем суммы
	local d_alpha_alpha = 0
	local d_delta_alpha = 0
	for i = 1, M do
		local pair = band[i]
		d_alpha_alpha = d_alpha_alpha + pair.d_alpha_2
		d_delta_alpha = d_delta_alpha + pair.d_delta_2
	end
	d_alpha_alpha = d_alpha_alpha / M
	d_delta_alpha = d_delta_alpha / M

	-- заносим результат в полосу
	band.d_alpha_alpha = d_alpha_alpha
	band.d_delta_alpha = d_delta_alpha
end

-- ошибки в перой полосе
print("bands_alpha[1].d_alpha_alpha", bands_alpha[1].d_alpha_alpha)
print("bands_alpha[1].d_delta_alpha", bands_alpha[1].d_delta_alpha)

-- считаем третьи дельты
for i = 1, N do
	local pair = _pairs[i]

	-- находим соотв. полосу
	local j = math.floor(pair.alpha_t % 360) + 1
	local band = bands_alpha[j]

	pair.d_alpha_3 = pair.d_alpha_2 - band.d_alpha_alpha
	pair.d_delta_3 = pair.d_delta_2 - band.d_delta_alpha
end

--------------------------------------------------------------------------------
-- деление по delta, четвёртые дельты
--------------------------------------------------------------------------------

-- разделяем пары по delta в 180 полос шириной 1 градус
-- [-90; -89), [-89; -88), ..., [89, 90)
local bands_delta = {}
for i = 1, 180 do
	bands_delta[i] = {}  -- создаём пустые полосы
end

for i = 1, N do
	local pair = _pairs[i]

	-- определяем номер полосы
	-- прибавляем 90, сдвигая delta в диапазон 0-180
	-- находим остаток от деления на 180
	-- чтобы быть уверенным, что delta в [0, 180)
	-- округляем вниз, получаем целые числа от 0 до 179
	-- прибавляем 1 так как полосы от 1 до 180
	local j = math.floor((pair.delta_t + 90) % 180) + 1

	-- добавляем пару в полосу
	table.insert(bands_delta[j], pair)
end

-- число пар в перой полосе
print("bands_delta[1]", #bands_delta[1])

-- для каждой полосы считаем ошибки
for j = 1, 180 do
	local band = bands_delta[j]
	local K = #band  -- число пар в полосе

	-- считаем суммы
	local d_alpha_delta = 0
	local d_delta_delta = 0
	for i = 1, K do
		local pair = band[i]
		d_alpha_delta = d_alpha_delta + pair.d_alpha_3
		d_delta_delta = d_delta_delta + pair.d_delta_3
	end
	d_alpha_delta = d_alpha_delta / K
	d_delta_delta = d_delta_delta / K

	-- заносим результат в полосу
	band.d_alpha_delta = d_alpha_delta
	band.d_delta_delta = d_delta_delta
end

-- ошибки в перой полосе
print("bands_delta[1].d_alpha_delta", bands_delta[1].d_alpha_delta)
print("bands_delta[1].d_delta_delta", bands_delta[1].d_delta_delta)

-- считаем четвёртые дельты
for i = 1, N do
	local pair = _pairs[i]

	-- находим соотв. полосу
	local j = math.floor((pair.delta_t + 90) % 180) + 1
	local band = bands_delta[j]

	pair.d_alpha_4 = pair.d_alpha_3 - band.d_alpha_delta
	pair.d_delta_4 = pair.d_delta_3 - band.d_delta_delta
end

--------------------------------------------------------------------------------
-- деление по магнитуде, пятые дельты
--------------------------------------------------------------------------------

-- разделяем пары по mag в сколько получится полос шириной 1 mag
-- ..., [1, 2), ...

local bands_mag = {}
local mag_min, mag_max = math.huge, -math.huge

-- заранее пустые полосы не создаём, так как не знаем их количество
-- создаём по надобности
for i = 1, N do
	local pair = _pairs[i]

	-- определяем номер полосы
	-- округляем вниз, получаем целые числа, в т.ч. и отрицательные
	local j = math.floor(pair.vmag_t)

	-- сохраняем номера минимальной и максимальной полос
	mag_min = math.min(mag_min, j)
	mag_max = math.max(mag_max, j)

	-- создаём пустую полосу если её нет
	bands_mag[j] = bands_mag[j] or {}

	-- добавляем пару в полосу
	table.insert(bands_mag[j], pair)
end

-- число пар в mag_min, mag_max полосах
print("bands_mag[mag_min]", #bands_mag[mag_min])
print("bands_mag[mag_max]", #bands_mag[mag_max])

-- для каждой полосы считаем ошибки
for j = mag_min, mag_max do
	local band = bands_mag[j]
	if band then
		local L = #band  -- число пар в полосе

		-- считаем суммы
		local d_alpha_m = 0
		local d_delta_m = 0
		for i = 1, L do
			local pair = band[i]
			d_alpha_m = d_alpha_m + pair.d_alpha_4
			d_delta_m = d_delta_m + pair.d_delta_4
		end
		d_alpha_m = d_alpha_m / L
		d_delta_m = d_delta_m / L

		-- заносим результат в полосу
		band.d_alpha_m = d_alpha_m
		band.d_delta_m = d_delta_m
	end
end

-- ошибки в mag_min, mag_max полосах
print("bands_mag[mag_min].d_alpha_m", bands_mag[mag_min].d_alpha_m)
print("bands_mag[mag_min].d_delta_m", bands_mag[mag_min].d_delta_m)
print("bands_mag[mag_max].d_alpha_m", bands_mag[mag_max].d_alpha_m)
print("bands_mag[mag_max].d_delta_m", bands_mag[mag_max].d_delta_m)

-- считаем пятые дельты
for i = 1, N do
	local pair = _pairs[i]

	-- находим соотв. полосу
	local j = math.floor(pair.vmag_t)
	local band = bands_mag[j]

	pair.d_alpha_5 = pair.d_alpha_4 - band.d_alpha_m
	pair.d_delta_5 = pair.d_delta_4 - band.d_delta_m
end

--------------------------------------------------------------------------------
-- деление по цвету, шестые дельты
--------------------------------------------------------------------------------

-- разделяем пары по mag в 7 полос по их цвету
local bands_color = {}
for i = 1, 7 do
	bands_color[i] = {}  -- создаём пустые полосы
end

-- функция для определения номера полосы
-- выделяем в отдельную функцию так как кода много и вызывается 2 раза

--   B-V
-- O −0.3
-- B −0.2
-- A 0
-- F +0.4
-- G +0.6
-- K +1.0
-- M +1.5

local function get_color(bmag, vmag)
	local bmv = bmag - vmag
	local j
	if bmv < -0.25 then    j = 1  -- O
	elseif bmv < -0.1 then j = 2  -- B
	elseif bmv < 0.2 then  j = 3  -- A
	elseif bmv < 0.5 then  j = 4  -- F
	elseif bmv < 0.8 then  j = 5  -- J
	elseif bmv < 1.25 then j = 6  -- K
	else                   j = 7  -- M
	end
	return j
end

for i = 1, N do
	local pair = _pairs[i]

	-- определяем номер полосы
	local j = get_color(pair.bmag_t, pair.vmag_t)

	-- добавляем пару в полосу
	table.insert(bands_color[j], pair)
end

-- число пар во всех полосах
for j = 1, 7 do
	print("bands_color[" .. j .. "]", #bands_color[j])
end

-- для каждой полосы считаем ошибки
for j = 1, 7 do
	local band = bands_color[j]
	local P = #band  -- число пар в полосе

	-- считаем суммы
	local d_alpha_sp = 0
	local d_delta_sp = 0
	for i = 1, P do
		local pair = band[i]
		d_alpha_sp = d_alpha_sp + pair.d_alpha_5
		d_delta_sp = d_delta_sp + pair.d_delta_5
	end
	d_alpha_sp = d_alpha_sp / P
	d_delta_sp = d_delta_sp / P

	-- заносим результат в полосу
	band.d_alpha_sp = d_alpha_sp
	band.d_delta_sp = d_delta_sp
end

-- ошибки во всех полосах
for j = 1, 7 do
	print("bands_color[" .. j .. "].d_alpha_sp", bands_color[j].d_alpha_sp)
	print("bands_color[" .. j .. "].d_delta_sp", bands_color[j].d_delta_sp)
end

-- считаем шестые дельты
for i = 1, N do
	local pair = _pairs[i]

	-- находим соотв. полосу
	local j = get_color(pair.bmag_t, pair.vmag_t)
	local band = bands_color[j]

	pair.d_alpha_6 = pair.d_alpha_5 - band.d_alpha_sp
	pair.d_delta_6 = pair.d_delta_5 - band.d_delta_sp
end

-- все альфы и дельты для первой пары
for i = 1, 6 do
	print("pair.d_alpha_" .. i, _pairs[1]["d_alpha_" .. i])
	print("pair.d_delta_" .. i, _pairs[1]["d_delta_" .. i])
end

--------------------------------------------------------------------------------
-- финал
--------------------------------------------------------------------------------

--считаем финальные ошибки
local ksi_alpha = 0
local ksi_delta = 0
for i = 1, N do
	local pair = _pairs[i]
	ksi_alpha = ksi_alpha + pair.d_alpha_6
	ksi_delta = ksi_delta + pair.d_delta_6
end
ksi_alpha = ksi_alpha / N
ksi_delta = ksi_delta / N

print("N:", N)
print("ksi_alpha:", ksi_alpha)
print("ksi_delta:", ksi_delta)

print("done")


