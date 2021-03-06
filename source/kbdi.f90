! *****************************************************************************
PROGRAM KEETCH_BYRAM_DROUGHT_INDEX
! *****************************************************************************
! This program calculates Keetch-Byran Drought Index

USE VARS
USE IO
USE SUBS

IMPLICIT NONE

INTEGER :: IBAND, IOS, IROW, ICOL, COUNT, J
CHARACTER(400) :: FN, NAMELIST_FN
REAL :: DENOM, DAILY_TMP_MAX, DAILY_PRECIP, EXPTERM, DF, EXCESSPRECIP

NAMELIST /KBDI_INPUTS/ INPUT_DIRECTORY, OUTPUT_DIRECTORY, TMP_FILENAME, PRECIP_FILENAME, &
                       PRECIP_AVG_FILENAME, KBDI0_FILENAME, KBDI_FILENAME, FAF_FILENAME, TMP_UNITS, &
                       NUM_INTERVALS_PER_DAY, PATH_TO_GDAL, SCRATCH, PRECIP_MULT

!Begin by getting input file name:
CALL GETARG(1,NAMELIST_FN)
IF (NAMELIST_FN(1:1)==' ') THEN
   WRITE(*,*) "Error, no input file specified."
   WRITE(*,*) "Hit Enter to continue."
   READ(5,*)
   STOP
ENDIF

!Now read NAMELIST group:
WRITE(*,*) 'Reading &KBDI_INPUTS namelist group from ', TRIM(NAMELIST_FN)

! Set defaults:
CALL SET_NAMELIST_DEFAULTS

! Open input file and read in namelist group
OPEN(LUINPUT,FILE=TRIM(NAMELIST_FN),FORM='FORMATTED',STATUS='OLD',IOSTAT=IOS)
IF (IOS .GT. 0) THEN
   WRITE(*,*) 'Problem opening input file ', TRIM(NAMELIST_FN)
   STOP
ENDIF

READ(LUINPUT,NML=KBDI_INPUTS,END=100,IOSTAT=IOS)
 100  IF (IOS > 0) THEN
         WRITE(*,*) 'Error: Problem with namelist group &KBDI_INPUTS.'
         STOP
      ENDIF
CLOSE(LUINPUT)

!Get operating system (linux or windows/dos)
CALL GET_OPERATING_SYSTEM

! Get coordinate system string
FN=TRIM(INPUT_DIRECTORY) // TRIM(TMP_FILENAME)
CALL GET_COORDINATE_SYSTEM(FN)

! Read input rasters:
CALL READ_BSQ_RASTER(TMP         ,INPUT_DIRECTORY, TMP_FILENAME       )
CALL READ_BSQ_RASTER(PRECIP      ,INPUT_DIRECTORY, PRECIP_FILENAME    )

IF (TRIM(KBDI0_FILENAME) .NE. 'null') THEN
   CALL READ_BSQ_RASTER(KBDI0  ,INPUT_DIRECTORY, KBDI0_FILENAME)
ELSE
   CALL ALLOCATE_EMPTY_RASTER(KBDI0  , TMP%NCOLS,TMP%NROWS,1,TMP%XLLCORNER,TMP%YLLCORNER,TMP%XDIM,TMP%YDIM,TMP%NODATA_VALUE,1,'FLOAT     ')
   KBDI0%RZT(:,:,:) = 400.0
ENDIF

IF (TRIM(PRECIP_AVG_FILENAME) .NE. 'null') THEN
   CALL READ_BSQ_RASTER(PRECIP_AVG  ,INPUT_DIRECTORY, PRECIP_AVG_FILENAME)
ELSE
   CALL ALLOCATE_EMPTY_RASTER(PRECIP_AVG  , TMP%NCOLS,TMP%NROWS,1,TMP%XLLCORNER,TMP%YLLCORNER,TMP%XDIM,TMP%YDIM,TMP%NODATA_VALUE,1,'FLOAT     ')
   PRECIP_AVG%RZT(:,:,:) = 20.0
ENDIF

! Convert TMP to F if necessary
SELECT CASE (TMP_UNITS)
   CASE ('C')
      TMP%RZT(:,:,:) = TMP%RZT(:,:,:) * 9./5. + 32.
   CASE ('F')
       CONTINUE
   CASE ('K')
      TMP%RZT(:,:,:) = ( TMP%RZT(:,:,:) - 273.15 ) * 9./5. + 32.
   CASE DEFAULT
      WRITE (*,*) 'Error:  TMP_UNITS must be one of C, F, or K'
END SELECT

! Allocate KBDI and fuel availability factor rasters:
CALL ALLOCATE_EMPTY_RASTER(KBDI  ,TMP%NCOLS,TMP%NROWS,TMP%NBANDS,TMP%XLLCORNER,TMP%YLLCORNER,TMP%XDIM,TMP%YDIM,TMP%NODATA_VALUE,1,'FLOAT     ')
CALL ALLOCATE_EMPTY_RASTER(FAF   ,TMP%NCOLS,TMP%NROWS,TMP%NBANDS,TMP%XLLCORNER,TMP%YLLCORNER,TMP%XDIM,TMP%YDIM,TMP%NODATA_VALUE,1,'FLOAT     ')

KBDI%RZT(1,:,:) = KBDI0%RZT(1,:,:)
FAF%RZT(1,:,:)  = 2E-6 * KBDI%RZT(1,:,:) * KBDI%RZT(1,:,:) + 0.72

WHERE(PRECIP%RZT(:,:,:) .LT. 0.) PRECIP%RZT(:,:,:) = 0.
PRECIP%RZT(:,:,:) = PRECIP_MULT * PRECIP%RZT(:,:,:) 

! Now calculate KBDI and FAF
DO IROW = 1, TMP%NROWS
DO ICOL = 1, TMP%NCOLS

!   IF (ABS(TMP%RZT(1,ICOL,IROW)-TMP%NODATA_VALUE) .GT. 0.1 .AND. ABS(PRECIP%RZT(1,ICOL,IROW) - PRECIP%NODATA_VALUE) .GT. 0.1) THEN
   IF (ABS(TMP%RZT(1,ICOL,IROW)-TMP%NODATA_VALUE) .GT. 0.1) THEN

      DENOM = 1E3 * (1.0 + 10.88 * EXP (-0.0441 * PRECIP_AVG%RZT(1,ICOL,IROW)))

      COUNT = 0
      DO IBAND = 1, TMP%NBANDS
         COUNT = COUNT + 1
         IF (COUNT .EQ. NUM_INTERVALS_PER_DAY + 1) COUNT = 1
         IF (COUNT .EQ. 1) THEN 
            DAILY_TMP_MAX = -9999.
            DAILY_PRECIP  = 0.
         ENDIF

         IF (TMP%RZT(IBAND,ICOL,IROW) .GT. DAILY_TMP_MAX) DAILY_TMP_MAX=TMP%RZT(IBAND,ICOL,IROW)
         DAILY_PRECIP = DAILY_PRECIP + PRECIP%RZT(IBAND,ICOL,IROW)

         IF (COUNT .EQ. NUM_INTERVALS_PER_DAY) THEN
            J = MAX(1,IBAND-NUM_INTERVALS_PER_DAY)
            EXPTERM = MAX ( 0.968 * EXP (0.0486 * DAILY_TMP_MAX) - 8.30, 0.0)
            DF = (800.0 - KBDI%RZT(J,ICOL,IROW)) * EXPTERM / DENOM
            EXCESSPRECIP = 100.0 * MAX(DAILY_PRECIP - 0.2, 0.0)
            KBDI%RZT(IBAND,ICOL,IROW) = (KBDI%RZT(J,ICOL,IROW) - EXCESSPRECIP) + DF
            KBDI%RZT(IBAND,ICOL,IROW) = MIN (KBDI%RZT(IBAND,ICOL,IROW), 800.0)
            KBDI%RZT(IBAND,ICOL,IROW) = MAX (KBDI%RZT(IBAND,ICOL,IROW),   0.0)
            FAF%RZT(IBAND,ICOL,IROW)  = 2E-6 * KBDI%RZT(IBAND,ICOL,IROW) * KBDI%RZT(IBAND,ICOL,IROW) + 0.72
            KBDI%RZT(J+1:IBAND-1,ICOL,IROW) = KBDI%RZT(IBAND,ICOL,IROW)  
            FAF%RZT (J+1:IBAND-1,ICOL,IROW) = FAF %RZT(IBAND,ICOL,IROW)  
         ENDIF
      ENDDO !IBAND
   ELSE
      KBDI%RZT(:,ICOL,IROW) = KBDI%NODATA_VALUE
      FAF%RZT (:,ICOL,IROW) = FAF %NODATA_VALUE
   ENDIF

ENDDO !ICOL
ENDDO !IROW

! Now write KBDI and FAF to disk:
CALL WRITE_BIL_RASTER(KBDI , OUTPUT_DIRECTORY, KBDI_FILENAME   , .TRUE., .TRUE.)
CALL WRITE_BIL_RASTER(FAF  , OUTPUT_DIRECTORY, FAF_FILENAME    , .TRUE., .TRUE.)

! *****************************************************************************
END PROGRAM KEETCH_BYRAM_DROUGHT_INDEX
! *****************************************************************************
