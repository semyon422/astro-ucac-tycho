local ffi = require("ffi")  -- для взаимодействия с кодом на си

-- модуль - таблица с функциями
-- в конце файла - return util
-- подключается так: local util = require("util")
local util = {}

-- функция для получения размера файла
function util.file_exist(path)
	local file = io.open(path, "rb")  -- открываем для чтения
	if not file then  -- файла нет
		return false
	end
	file:close()  -- закрываем файл
	return true  -- файл есть
end

-- функция для получения размера файла
function util.get_file_size(path)
	local file = assert(io.open(path, "rb"))  -- открываем для чтения
	local size = file:seek("end")  -- перемещаяемся в конец файла - получаем размер
	file:close()  -- закрываем файл
	return size
end

-- функция для получения содержимого файла
function util.read_file(path)
	local file = assert(io.open(path, "rb")) -- открываем для чтения
	local data = file:read("*a")  -- читаем целиком
	file:close()  -- закрываем файл
	return data
end

-- функция для разбиения строки на подстроки, делитель - запятая
-- использовать как итератор
function util.split(s, p)
	if not p then
		return
	end
	local a, b = s:find(",", p, true)
	if not a then
		return false, s:sub(p)
	end
	return b + 1, s:sub(p, a - 1)
end

-- функция чтения csv файла в массив структур
function util.read_file_csv(path, ctype, fields_map)
	local file = assert(io.open(path, "r"))  -- открываем для чтения

	local header = file:read("*l")  -- читаем 1ю строку - в ней шапка таблицы

	-- разбиваем строку-заголовок на подстроки-поля
	-- получаем массив из названий полей таблицы
	-- нужен для получения имени столбца по его номеру
	local fields = {}
	for _, field in util.split, header, 1 do
		table.insert(fields, field)
	end

	-- считаем количество строк в файле
	-- необходимо это для того, чтобы знать, сколько выделять памяти под массив структур
	local lines_count = 1  -- 1ю строчку уже проситали, поэтому начинаем с 1
	for _ in file:lines() do
		lines_count = lines_count + 1
	end

	-- создаём массив из lines_count структур типа ctype (передан в read_file_csv)
	local entries = ffi.new(ctype .. "[?]", lines_count)

	file:seek("set", 0)  -- переходим в начало файла
	file:read("*l")  -- снова читаем заголовок чтоб пропустить его

	local offset = 0  -- позиция текущей записи, а также количество записей
	-- после прочтения всего файла может быть меньше чем lines_count
	-- так как могут попасться строки, которые мы считаем невалидными

	for line in file:lines() do
		local entry = entries[offset]  -- текущая запись, изначально всё заполнено нулями
		local i = 1  -- счётчик столбцов, нужен для... (см fields выше)

		for _, value in util.split, line, 1 do  -- разбиваем строку запятыми
			value = tonumber(value)  -- преобразуем значение из строки в число
			local column = fields[i]  -- получаем имя колонки в таблице
			local field = fields_map[column]  -- получаем имя поля в структуре
			if field then  -- поле в структуре есть
				if not value then  -- преобразование значения в число не удалось
					break  -- прерываем цикл и пропускаем текущую строку
				end
				entry[field] = value
			end
			i = i + 1
		end

		-- если не был вызван break, значит все колонки были успешно обработаны
		-- и условие нижу выполняется
		if i == #fields + 1 then
			offset = offset + 1
		end

		-- если со строкой что-то не так, (число не получилось или колонок меньше чем в заголовке)
		-- то пробуем записать в этот же entry уже следующую строку
	end

	file:close()  -- закрываем файл

	return entries, offset
end

-- функция для поиска пар значений в двух отсортированных массивах

-- p_a, p_b - входные массивы (индексы с 0)
-- size_a, size_b - размеры массивов (число элементов)
-- compare - функция сравнения

-- функция сравнения принимает элементы из 1го и 2го массива,
-- если мы считаем элементы равными, возвращаем 0
-- если 2й больше 1го, возвращаем любое положительное число
-- если 1й больше 2го, возвращаем любое отрицательное число

-- если мы считаем элементы частично равными, ничего не возвращаем
-- в таком случае алгоритм будет работать, как если бы элементы были равны,
-- но не добавит их в список пар

-- каждая пара это таблица с двумя числами - индексами значений, а не самими значениями:
-- {index_a, index_b}

function util.find_pairs(p_a, p_b, size_a, size_b, compare)
	local _pairs = {}  -- массив с парами

	-- начинаем поиск в начале массивов
	local pos = {0, 0}  -- текущие индексы элементов 1го и 2го массива
	while pos[1] < size_a and pos[2] < size_b do
		local pos_b = pos[2]  -- заносим второй индекс во временную переменную
		-- нам потребуется менять её независимо от основной

		local res = compare(p_a[pos[1]], p_b[pos_b])  -- сравниваем 2 элемента
		while not res or res == 0 do  -- пока элементы считаем равными
			if res == 0 then  -- функция compare выдала что это пара
				table.insert(_pairs, {pos[1], pos_b})
			end
			pos_b = pos_b + 1  -- идём вправо по 2му массиву, ...
			if pos_b == size_b then  -- проверка на выход за пределы 2го массива
				res = 1  -- указываем на то что нужно продвинуться вправо в 1ом массиве
				break  -- и выходим из цикла
			end
			res = compare(p_a[pos[1]], p_b[pos_b])  -- ... сравнивая элемент 2го с элементом 1го
		end

		-- если результат сравнения не равен 0,
		-- двигаемся вправо в том массиве, в котором текущая звезда отстаёт
		-- от текущей звезды в другом массиве
		if res > 0 then
			pos[1] = pos[1] + 1
		elseif res < 0 then
			pos[2] = pos[2] + 1
		end
	end

	return _pairs
end

-- тест для функции util.read_file_csv
-- даны 2 массива с количеством пар равным 32

local list_a = {[0] = 0, 0.01, 0.02, 0.03,    1, 1.01,    2, 2.01, 2.02, 2.03,    3, 3.01}
local list_b = {[0] = 0, 0.01,    1, 1.01, 1.02, 1.03,    2, 2.01,    3, 3.01, 3.02, 3.03}

local _pairs = util.find_pairs(list_a, list_b, 12, 12, function(a, b)
	local delta = b - a
	if math.abs(delta) <= 0.1 then
		return 0
	elseif delta > 0 then
		return 1
	elseif delta < 0 then
		return -1
	end
end)

assert(#_pairs == 32)

-- возвращаем наш модуль
return util
