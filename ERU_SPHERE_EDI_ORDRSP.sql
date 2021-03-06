USE [CBTrade]
GO
/****** Object:  StoredProcedure [dbo].[ERU_SPHERE_EDI_ORDRSP]    Script Date: 08.09.2021 11:14:43 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
--============================================================================================================================================================= 
-- Author:		Tsvetkov Alexander
-- Create date: 06.09.2021 
-- Description:	Процедура формирования документа "Подтверждение заказа" (ORDRSP) в XML формата для "Сфера-EDI" 
-- Test:        exec ERU_SPHERE_EDI_ORDRSP 1315954               -- единственный параметр - номер заказа в ЛиС
--============================================================================================================================================================= 
   
ALTER procedure [dbo].[ERU_SPHERE_EDI_ORDRSP]      
	@ID_HD_ZAK int = null
as              
              
SET NOCOUNT ON   
            
declare @x xml

select top 1 @x = SOURCE 
from R_HD_EDI_ZAK
where ID_HD_ZAK = @ID_HD_ZAK

--=============================================================================================================================================================    
--     ФОРМИРОВАНИЕ ДОКУМЕНТА: Хидер - то, что до товарной части 
--=============================================================================================================================================================

--Функциональное предназначение документа (4 - изменение, 27 - отмена, 29 - полная акцептация)
declare @zak_status smallint
select top 1 @zak_status = t2.ZAK_STATUS
from (  select t.IDDOC, case when sum(t.QNTY)=sum(t.DIFF) then 27 when sum(t.DIFF)=0 then 29 else 4 end ZAK_STATUS
		from
			(select egz.IDDOC, egz.ART1, egz.ID_GOOD,
				egz.QNTY,
				gz.KOL_GOOD_R,
				abs(egz.QNTY - IsNull(gz.KOL_GOOD_R,0)) as DIFF
			from R_HD_EDI_ZAK rhez
			left join R_GOOD_EDI_ZAK egz on rhez.IDDOC = egz.IDDOC
			left join R_GOOD_ZAK gz with (NOLOCK) on egz.ID_GOOD_ZAK = gz.ID_GOOD_ZAK
			where rhez.ID_HD_ZAK = @ID_HD_ZAK) t
		group by t.IDDOC ) t2
--Меняем название корня документа
set @x = @x.query('element ORDRSP {ORDERS/@*, /ORDERS/*}')
--Номер документа ответа на заказ; заодно запомним идентификатор IDDOC
declare @doc_number varchar(30), @doc_number_answer varchar(35), @dat_zak_create varchar(10), @IDDOC int, @DAT_ZAK varchar(10), @NOM_ZAK varchar(15), @DAT_V_ZAK varchar(10), @QNTY varchar(5)
select @IDDOC = n.value('(UNH[1]/E0062[1])', 'int'), 
  @doc_number = n.value('(BGM[1]/C106[1]/E1004[1])', 'varchar(30)'),
  @doc_number_answer = 'ORSP_' + n.value('(BGM[1]/C106[1]/E1004[1])', 'varchar(30)'),
  @dat_zak_create = n.value('(DTM[1]/C507[1]/E2380[1])', 'varchar(10)'),
  @QNTY = n.value('(CNT[1]/C270[1]/E6066[1])', 'varchar(5)')    
from @x.nodes('ORDRSP') t (n);	
if @x is not null 
  begin
	set @x.modify('replace value of (/ORDRSP/BGM/C106/E1004/text())[1] with (sql:variable("@doc_number_answer"))')
	--Атрибуты заказа в ЛиС
	select @DAT_ZAK = replace(Convert(varchar(50), z.DAT_ZAK, 102), '.', ''), 
	  @DAT_V_ZAK = replace(Convert(varchar(50), z.DAT_V_ZAK, 102), '.', ''), 
	  @NOM_ZAK = z.NOM_ZAK 
	from R_HD_ZAK z
	join R_HD_EDI_ZAK ez on z.ID_HD_ZAK = ez.ID_HD_ZAK
	where ez.IDDOC = @IDDOC
	--Номер электронного сообщения
	declare @msg_num varchar(14)
	set @msg_num = 'MSG_' + dbo.GET_GLOBAL_VAR('MSG_EANCOM') + '_' + @NOM_ZAK;   -------------------------  ДОБАВИТЬ СЧЁТЧИК В СЛУЧАЕ УСПЕШНОЙ ОТПРАВКИ
	set @x.modify('replace value of (/ORDRSP/UNH/E0062/text())[1] with (sql:variable("@msg_num"))')
	--Меняем обозначение документа
	set @x.modify('replace value of (/ORDRSP/UNH/S009/E0065/text())[1] with ("ORDRSP")')
	--Меняем код документа
	set @x.modify('replace value of (/ORDRSP/BGM/C002/E1001/text())[1] with ("231")')
	--Функциональное предназначение документа 
	set @x.modify('replace value of (/ORDRSP/BGM/E1225/text())[1] with (sql:variable("@zak_status"))')
	--Дата документа
	set @x.modify('replace value of (/ORDRSP/DTM[1]/C507/E2380/text())[1] with (sql:variable("@DAT_ZAK"))')
	--Подтвержденная дата доставки
	set @x.modify('replace value of (/ORDRSP/DTM[2]/C507/E2005/text())[1] with ("2")')
	set @x.modify('delete (/ORDRSP/DTM[2]/C507/E2380)')
	set @x.modify('delete (/ORDRSP/DTM[2]/C507/E2379)')
	set @x.modify('insert <E2380>temp</E2380> into (/ORDRSP/DTM[2]/C507)[1]')
	set @x.modify('replace value of (/ORDRSP/DTM[2]/C507/E2380/text())[1] with (sql:variable("@DAT_V_ZAK"))')
	set @x.modify('insert <E2379>102</E2379> into (/ORDRSP/DTM[2]/C507)[1]')
	set @x.modify('delete (/ORDRSP/DTM[4])')
	set @x.modify('delete (/ORDRSP/DTM[3])')
	--Номер заказа ТС
	set @x.modify('insert text{sql:variable("@doc_number")} into (/ORDRSP/SG1[1]/RFF/C506/E1154)[1]')
	--Дата создания заказа
	set @x.modify('insert text{sql:variable("@dat_zak_create")} into (/ORDRSP/SG1[1]/DTM/C507/E2380)[1]')
	set @x.modify('delete (/ORDRSP/SG1[2])')
	--Продавец/покупатель
	set @x.modify('delete (/ORDRSP/SG2/SG3)')
	set @x=cast(replace(cast(@x as nvarchar(max)), 'SG2>', 'SG3>') as xml)
	set @x.modify('delete (/ORDRSP/SG3[5])')
	set @x.modify('delete (/ORDRSP/SG3[4])')
	set @x.modify('delete (/ORDRSP/SG3/NAD/C080)')
	set @x.modify('delete (/ORDRSP/SG3/NAD/E3036)')
	set @x.modify('delete (/ORDRSP/SG3/NAD/C059)')
	set @x.modify('delete (/ORDRSP/SG3/NAD/E3164)')
	set @x.modify('delete (/ORDRSP/SG3/NAD/E3251)')
	set @x.modify('delete (/ORDRSP/SG3/NAD/E3207)')
	--Меняем местами покупятеля и продавца (в заказе так, в подтверждении - наоборот)
	set @x.modify('insert /ORDRSP/SG3[2] after (/ORDRSP/SG1[1])[1]')
	set @x.modify('delete (/ORDRSP/SG3[3])')

	set @x.modify('delete (/ORDRSP/SG7)')
	set @x.modify('delete (/ORDRSP/SG12)')
	--Удаляем все узлы начиная с товарной части
	set @x.modify ('delete (/ORDRSP/SG28)')
	set @x.modify ('delete (/ORDRSP/UNS)')
	set @x.modify ('delete (/ORDRSP/MOA)')
	set @x.modify ('delete (/ORDRSP/CNT)')
	set @x.modify ('delete (/ORDRSP/UNT)')
  end

--=============================================================================================================================================================    
--     ФОРМИРОВАНИЕ ДОКУМЕНТА: Товарная часть   
--=============================================================================================================================================================

declare @goods xml

select @goods = (
	select egz.ORDERNUM as 'LIN/E1082', 
	  '3' as 'LIN/E1229',
	  '' as 'LIN/C212/E7140',         -- Штрих-код
	  'SRV' as 'LIN/C212/E7143',
	  '1' as 'PIA/E4347',  
	  egz.ART1 as 'PIA/C212/E7140',   -- Код товара покупателя
	  'IN' as 'PIA/C212/E7143',
	  'temp' as 'TEMP',               -- Вставляем разделитель, чтобы проще сформировать два одноимённых узла; его потом удаляем
	  '1' as 'PIA/E4347',
	  gz.ID_GOOD as 'PIA/C212/E7140', -- Код товара продавца
	  'SA' as 'PIA/C212/E7143',
	  'F' as 'IMD/E7077',
	  egz.NAIM as 'IMD/C273/E7008', 
	  '21' as 'QNT/C186/E6063', -- Заказанное 
	  egz.QNTY as 'QNT/C186/E6060',
	  'temp' as 'TEMP',
	  '170' as 'QNT/C186/E6063',
	  egz.QNTY as 'QNT/C186/E6060',
	  gz.KOL_GOOD_R
	from R_HD_EDI_ZAK rhez
	left join R_GOOD_EDI_ZAK egz on rhez.IDDOC = egz.IDDOC
	left join R_GOOD_ZAK gz with (NOLOCK) on egz.ID_GOOD_ZAK = gz.ID_GOOD_ZAK
	where gz.ID_HD_ZAK = @ID_HD_ZAK
	order by egz.ORDERNUM
	for xml path(''), type, ROOT ('SG26') )

if @x is not null set @goods.modify('delete (/SG26/TEMP)') -- Удаляем разделители

--=============================================================================================================================================================    
--     ФОРМИРОВАНИЕ ДОКУМЕНТА: Футер   
--=============================================================================================================================================================

declare @footer xml

select @footer = 

	(select 
	
		(select 'S' as 'UNS/E0081'
		for xml path(''), type),

		(select 'S' as 'CNT/C270/E6069',
		 @QNTY as 'CNT/C270/E6066',
		 '' as 'UNT/E0074',
		 @msg_num as 'UNT/E0062'
		for xml path(''), type ) 

	for xml PATH(''), type) 

--=============================================================================================================================================================    
--     ФОРМИРОВАНИЕ ДОКУМЕНТА: Сборка из всех полученных частей   
--=============================================================================================================================================================

set @x = cast( replace(replace(cast(@x as nvarchar(max)), '<ORDRSP>', ''), '</ORDRSP>', '') as xml )

select @x = 
	(select 	
		(select @x),
		(select @goods),		
		(select @footer) 
	for xml PATH(''), type, root('ORDRSP')) 

--=============================================================================================================================================================    
--     СОХРАНЕНИЕ ДОКУМЕНТА В ФАЙЛ   
--=============================================================================================================================================================

-- Чтобы обратиться из конекта BCP создадим глобальную таблицу и поместим туда дату и время пользователя
if object_id(N'tempdb..##t747') is not null drop table ##t747

declare @suser nvarchar(128), @where_create varchar(50)
select @suser = SUSER_NAME(), @where_create = Cast(Convert(datetime, GetDate(), 113) as varchar(50))

select @x as x, @suser as suser, @where_create as where_create 
into ##t747

declare @sqlStr varchar(1000), @fileName varchar(200), @sqlCmd varchar(1000)
 
set @fileName = 'E:\tempmssql\' + 'ORDRSP' + @doc_number + '.xml' 
set @sqlStr = 'select Cast(x as xml) from ##t747 where suser = ''' + @suser +''' and where_create = ''' + @where_create + ''''
select @sqlCmd = 'bcp "' + @sqlStr + '" queryout ' + @fileName + ' -S (local) -T -w -C 1251 -r' -- Сохранит не в нужной нам кодировке, необходима служба для перекодировки и перемещения в папку отправки

exec xp_cmdshell @sqlCmd

-- Удаляем таблицу с уникальным именем
if object_id(N'tempdb..##t747') is not null drop table ##t747



