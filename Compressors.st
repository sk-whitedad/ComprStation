VAR_GLOBAL CONSTANT
END_VAR
VAR_GLOBAL
	on_off AT %IB1.0: BYTE; (* Входы ПЛК, указывает о включении компрессора *)
	original_8AC AT %QB6.1.0 : ARRAY[1..7] OF struct_original_8AC;
	Compr_Alarm AT %QB3.0 : BYTE := 0;


(*	Уставки	*)
	t_ust_1st  AT %QW7.2.0	:WORD;
	t_ust_2st AT %QW7.3.0	:WORD ;
	t_ust_oil AT %QW7.4.0	:WORD;
	P_ust_1st AT %QD7.5.0	:REAL;
	P_ust_2st AT %QD7.6.0	:REAL;
	P_ust_oil_min AT %QD7.7.0	:REAL;
	P_ust_oil_max AT %QD7.8.0	:REAL;
	P_ust_water AT %QD7.9.0	:REAL ;
END_VAR

TYPE AI :
STRUCT
 	ai	: ARRAY[1..8] OF struct_ai;
END_STRUCT
END_TYPE

TYPE COMPRESSOR :
STRUCT
	bSignal1	:BYTE;
	bSignal2	:BYTE;
	t_1st	:INT;
	t_2st	:INT;
	t_oil	:INT;
	P_1st	:REAL;
	P_2st	:REAL;
	P_oil	:REAL;
	P_water	:REAL;
END_STRUCT
END_TYPE

TYPE enum_AlarmType:
(
	temp_1st  := 0,
	temp_2st := 1,
	temp_oil :=  2,
	davl_1st :=  3,
	davl_2st :=  4,
	davl_oil_min := 5,
	davl_oil_max :=  6,
	davl_water :=  7
);
END_TYPE

TYPE enum_status:
(
	status_ok := 0,
	status_not_correct :=  16#F000,
	status_data_not_ready :=  16#F006,
	status_sensor_disabled :=  16#F007,
	status_value_high :=  16#F00A,
	status_value_low :=  16#F00B,
	status_break := 16#F00D,
	status_Incorrect_calibration :=  16#F00F
);
END_TYPE

TYPE struct_ai :STRUCT
	status : enum_status;
 	cyclic : WORD;
	value : REAL;
END_STRUCT
END_TYPE

TYPE	struct_original_8AC :STRUCT
	command : DWORD;
	SRD : ARRAY[1..8] OF INT;
	Read : ARRAY[1..8,1..3] OF WORD;
	x : STRING(15); 	(*нужный мусор чтобы заполнить стринг до 79*)
END_STRUCT
END_TYPE



PROGRAM PLC_PRG
VAR
(*	SRD: 280-287, Read: 288-311	*)
	compressors AT %QD7.10.0 	:ARRAY [1..7] OF COMPRESSOR;
	ai : ARRAY[1..8] OF struct_ai;
	p : POINTER TO DWORD;
	i, k: INT;
	all_ai	: ARRAY[1..7] OF AI;

	timer_start: TIME := T#10s;(*Время таймера по отсечке по маслу при включении*)
	TON_: ARRAY[1..7] OF TON; (*Таймеры для давления масла при старте на каждый компрессор*)
END_VAR
(* назначение каналов в ai
1 - Температура воздуха 1 ступени
2 - Температура воздуха 2 ступени
3 - Темпреатура масла
4 - Давление воздуха 1 ступени
5 - Давление воздуха 2 ступени
6 - Давление масла
7 - Давление воды
*)

(* расшифровка bSignal1
bSignal.0 - темп. 1ст.
bSignal.1 - темп. 2ст.
bSignal.2 - давл. 1ст.
bSignal.3 - давл. 2ст.
bSignal.4 - темп. масла
bSignal.5 - давл. масла
bSignal.6 - давл. воды.
bSignal.7 - включен/выключен компрессор
*)

(*	расшифровка каналов ai[1..8]
1 - датчик температуры 1 ступени
2 - датчик температуры 2 ступени
3 - датчик температуры масла
4 - датчик давления 1 ступени
5 - датчик давления 2 ступени
6 - датчик давления масла
7 - датчик давления воды
*)

ust_T1st := 180;
ust_T2st := 180;
ust_Toil := 80;
ust_P1st := 8;
ust_P2st := 8;
ust_Poil_min := 1;
ust_Poil_max := 6;
ust_Pwater := 0.5;

IF last_error = 0 THEN
  k := DWORD_TO_INT( last_address - 15);
  CASE k OF 1..7:
      compressors[k].bSignal1 := 0;
      compressors[k].bSignal2 := 0;
 	IF  BIT_OF_BYTE(on_off, (k - 1)) = TRUE THEN (* Если компрессор включен то выполняем считывание и заполнение данными*)
      compressors[k].bSignal1 := 1;
	    FOR i := 1 TO 8 DO (* Записываем данные по 8 каналам МВ*)
       	  all_ai[k].ai[i].status := original_8AC[k].SRD[i];
	 	   p := ADR(all_ai[k].ai[i].value);
	 	   p^ := 0;
	 	   all_ai[k].ai[i].cyclic := 0;

			IF original_8AC[k].SRD[i] = 0 THEN (* если статус измерения успешен*)
		  		all_ai[k].ai[i].cyclic := original_8AC[k].Read[i,3];
		 		 p^ := original_8AC[k].Read[i,1] * 16#10000 + original_8AC[k].Read[i,2];

					CASE i OF
					1 : 	compressors[k].t_1st := REAL_TO_INT( all_ai[k].ai[i].value );
					2 : 	compressors[k].t_2st := REAL_TO_INT (all_ai[k].ai[i].value );
					3 : 	compressors[k].t_oil := REAL_TO_INT ( all_ai[k].ai[i].value );
					4 : 	compressors[k].P_1st := all_ai[k].ai[i].value;
					5 : 	compressors[k].P_2st := all_ai[k].ai[i].value;
					6 : 	compressors[k].P_oil := all_ai[k].ai[i].value;
					7 : 	compressors[k].P_water := all_ai[k].ai[i].value;
					END_CASE;

					IF compressors[k].t_1st  > ust_T1st THEN
							compressors[k].bSignal2.0 := Alarm(k, temp_1st);(*Аларм по температуре 1 ступени*)
					END_IF
					IF compressors[k].t_2st  > ust_T2st THEN
						compressors[k].bSignal2.1 := Alarm(k, temp_2st);(*Аларм по температуре 2 ступени*)
					END_IF
					IF compressors[k].t_oil  > ust_Toil THEN
						compressors[k].bSignal2.2 := Alarm(k, temp_oil);(*Аларм по температуре масла*)
					END_IF
					IF compressors[k].P_1st  > ust_P1st THEN
						compressors[k].bSignal2.3 := Alarm(k, davl_1st);(*Аларм по давлению 1 ступени*)
					END_IF
					IF compressors[k].P_2st  > ust_P2st THEN
						compressors[k].bSignal2.4 := Alarm(k, davl_2st);(*Аларм по давлению 2 ступени*)
					END_IF

				(* Таймер при включении компрессора от сработки по нижнему давлению масла*)
				TON_[k]( IN := BYTE_TO_BOOL( compressors[k].bSignal1), PT := timer_start );
				IF TON_[k].Q  THEN
					IF compressors[k].P_oil  < ust_Poil_min  THEN
						compressors[k].bSignal2.5 := Alarm(k, davl_oil_min);(*Аларм по мин. давлению масла*)
					END_IF
				END_IF
					IF  compressors[k].P_oil  > ust_Poil_max THEN
						compressors[k].bSignal2.5 := Alarm(k, davl_oil_max);(*Аларм по макс. давлению масла*)
					END_IF
					IF compressors[k].P_water  < ust_Pwater THEN
						(*compressors[k].bSignal2.6 := Alarm(k, davl_water)*);(*Аларм по давлению воды*)
					END_IF

			END_IF
	    END_FOR
	ELSE 	TON_[k]( IN := BYTE_TO_BOOL( compressors[k].bSignal1), PT := T#0s );(* Если компрессор выключен то таймер обнуляем*)
	END_IF
  END_CASE
END_IF

last_error := 0;

END_PROGRAM