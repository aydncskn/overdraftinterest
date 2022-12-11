with OVERDRAFTTABLE AS 
                (
                    SELECT LAST_DAY(TRANSACTIONDATE)-1 TRANSACTIONDATE, NULL TRANSACTION_TYPE,  NULL AMOUNT, NULL BALANCE
                      FROM (SELECT max(TRANSACTIONDATE) TRANSACTIONDATE FROM BALANCE_SHEET)
                    UNION ALL 
                    SELECT TRANSACTIONDATE, TRANSACTION_TYPE, AMOUNT, BALANCE
                      FROM BALANCE_SHEET
                    UNION ALL 
                    SELECT TRUNC(TRANSACTIONDATE,'MM')-1 TRANSACTIONDATE, NULL TRANSACTION_TYPE,  NULL AMOUNT, NULL BALANCE
                     FROM (SELECT TRUNC(max(TRANSACTIONDATE)) TRANSACTIONDATE FROM BALANCE_SHEET)
                ),

GAPTABLE AS 
                (
                   SELECT  TRANSACTIONDATE, TRANSACTION_TYPE, AMOUNT, BALANCE,
                           TRUNC(LEAD(TRANSACTIONDATE,1,TRANSACTIONDATE) OVER(ORDER BY TRANSACTIONDATE)) - TRUNC(TRANSACTIONDATE) + 1  GAP
                     FROM  OVERDRAFTTABLE
                ),

BALANCE_SHEET_ALL_DAYS AS
               ( SELECT  TO_CHAR(CASE WHEN LEVELL  = GAP THEN TRANSACTIONDATE ELSE TRUNC(TRANSACTIONDATE) + LEVELL  END,'DD.MM.YYYY HH24:MI:SS') TRANSACTIONDATE2,
                         CASE WHEN LEVELL  = GAP THEN TRANSACTION_TYPE END TRANSACTION_TYPE2,
                         CASE WHEN LEVELL  = GAP THEN AMOUNT END AMOUNT2,
                         BALANCE BALANCE2
                  FROM  GAPTABLE,
                      LATERAL (
                              SELECT  LEVEL LEVELL                        
                              FROM  DUAL                  
                              CONNECT BY LEVEL <= GAP
                              )
                ORDER BY CASE WHEN LEVELL = GAP THEN TRANSACTIONDATE ELSE TRUNC(TRANSACTIONDATE) + LEVELL END DESC
               ),

BALANCE_SHEET_WITH_BALANCE_PREVIOUS AS              
               (
                SELECT  TO_DATE(TRANSACTIONDATE2, 'DD.MM.YYYY HH24:MI:SS') TRANSACTIONDATE2, 
                        AMOUNT2, 
                        BALANCE2, 
                        LAG(BALANCE2, 1, BALANCE2) OVER (ORDER BY TO_DATE(TRANSACTIONDATE2, 'DD.MM.YYYY HH24:MI:SS')) BALANCEPREVIOUS
                  FROM  BALANCE_SHEET_ALL_DAYS 
                  ORDER BY TO_DATE(TRANSACTIONDATE2, 'DD.MM.YYYY HH24:MI:SS') DESC
              ),
BALANCE_SHEET_WITH_INTERESTBASEAMOUNT  AS               
              (  SELECT TRANSACTIONDATE2, 
                        AMOUNT2, 
                        BALANCE2, 
                        BALANCEPREVIOUS, 
                        CASE WHEN TRANSACTIONDATE2 = TRUNC(TRANSACTIONDATE2) AND BALANCE2 < 0 THEN BALANCE2
                             WHEN BALANCEPREVIOUS < 0 AND AMOUNT2 < 0 THEN AMOUNT2 
                             WHEN BALANCEPREVIOUS > 0 AND AMOUNT2 < 0 AND BALANCE2 < 0 THEN BALANCE2 
                             ELSE 0 END INTERESTBASEAMOUNT 
                 FROM   BALANCE_SHEET_WITH_BALANCE_PREVIOUS
              ),

CALENDARTABLE2 AS
         (
         SELECT MATCHINGPATTERN, CALENDAR_DAY, ISHOLIDAY
                FROM CALENDARTABLE 
                MATCH_RECOGNIZE(
                ORDER BY CALENDAR_DAY
                MEASURES MATCH_NUMBER() AS MATCHINGPATTERN
                ALL ROWS PER MATCH
                PATTERN(NO YES+ | NO )
                DEFINE   YES AS UPPER(ISHOLIDAY) = 'YES', NO AS UPPER(ISHOLIDAY) = 'NO')
        ),
        
CALENDARTABLEJOINED AS       
        (
        SELECT MATCHINGPATTERN, 
               CALENDAR_DAY , 
               TRANSACTIONDATE2 , 
               ISHOLIDAY,  
               INTERESTBASEAMOUNT
        FROM BALANCE_SHEET_WITH_INTERESTBASEAMOUNT JOIN CALENDARTABLE2 ON  TRUNC(TRANSACTIONDATE2) = CALENDAR_DAY
        ORDER BY CALENDAR_DAY DESC),
        
CALENDARTABLEJOINED2 AS
       (
        SELECT MATCHINGPATTERN,
               COUNT(MATCHINGPATTERN)  HOW_MANY_MATCHING_DAYS,
               MIN(TRANSACTIONDATE2) TRANSACTIONDATE2,
               MIN(INTERESTBASEAMOUNT) KEEP(DENSE_RANK FIRST ORDER BY TO_DATE(TRANSACTIONDATE2, 'DD.MM.YYYY HH24:MI:SS')) INTERESTBASEAMOUNT
        FROM CALENDARTABLEJOINED
        WHERE TRANSACTIONDATE2 = TRUNC(TRANSACTIONDATE2)
        GROUP BY MATCHINGPATTERN
UNION ALL 
        SELECT MATCHINGPATTERN,
               0 HOW_MANY_MATCHING_DAYS,
               TRANSACTIONDATE2,
               INTERESTBASEAMOUNT
        FROM CALENDARTABLEJOINED
        WHERE TRANSACTIONDATE2 <> TRUNC(TRANSACTIONDATE2)
        ),

INTERESTBASEGROUPED AS
       (
        SELECT MATCHINGPATTERN,
               SUM(HOW_MANY_MATCHING_DAYS)HOW_MANY_MATCHING_DAYS,
               MIN(TRANSACTIONDATE2) TRANSACTIONDATE2,
               SUM(INTERESTBASEAMOUNT) INTERESTBASEAMOUNT
        FROM CALENDARTABLEJOINED2 
        GROUP BY MATCHINGPATTERN
       )
      
SELECT ROUND(SUM((HOW_MANY_MATCHING_DAYS* INTERESTBASEAMOUNT)*(2/(100*30))),2) OVERDRAFTINTEREST
FROM INTERESTBASEGROUPED 