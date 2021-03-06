! *****************************************************************************
PROGRAM RANK_RASTERS
! *****************************************************************************
! This program ranks the pixels in two multiband rasters according to 
! the pixel value from the first raster 

USE VARS, ONLY : RASTER_TYPE, INPUT_DIRECTORY, OUTPUT_DIRECTORY
USE SORT
USE SUBS
USE IO

IMPLICIT NONE

INTEGER :: IOS, IROW, ICOL, IRAS, NRASTERS_TO_RANK
REAL, ALLOCATABLE, DIMENSION(:,:,:) :: X, Y
CHARACTER(400) :: FN, NAMELIST_FN, RANKER_FILENAME_IN, RANKEE_FILENAME_IN(1:100), RANKER_FILENAME_OUT, RANKEE_FILENAME_OUT(1:100), &
                  RANKEE_PEAK_FILENAME_OUT(1:100), RANKER_PEAK_FILENAME_OUT
LOGICAL :: DUMP_RANKER, DUMP_SORTED_RASTERS, DUMP_PEAK_RASTERS
TYPE (RASTER_TYPE) :: RANKER, RANKEE(1:100), PEAK

NAMELIST /RANK_RASTERS_INPUTS/ INPUT_DIRECTORY, OUTPUT_DIRECTORY, NRASTERS_TO_RANK, RANKER_FILENAME_IN, RANKEE_FILENAME_IN, &
                               RANKER_FILENAME_OUT, RANKEE_FILENAME_OUT, RANKEE_PEAK_FILENAME_OUT, RANKER_PEAK_FILENAME_OUT, &
                               COMPRESS, DUMP_RANKER, DUMP_SORTED_RASTERS, PATH_TO_GDAL, SCRATCH, DUMP_PEAK_RASTERS

!Begin by getting input file name:
CALL GETARG(1,NAMELIST_FN)
IF (NAMELIST_FN(1:1)==' ') THEN
   WRITE(*,*) "Error, no input file specified."
   WRITE(*,*) "Hit Enter to continue."
   READ(5,*)
   STOP
ENDIF

!Now read NAMELIST group:
WRITE(*,*) 'Reading &RANK_RASTERS_INPUTS namelist group from ', TRIM(NAMELIST_FN)

! Set defaults:
CALL SET_NAMELIST_DEFAULTS
NRASTERS_TO_RANK    = 1
DUMP_RANKER         = .FALSE. 
DUMP_SORTED_RASTERS = .TRUE. 

! Open input file and read in namelist group
OPEN(LUINPUT,FILE=TRIM(NAMELIST_FN),FORM='FORMATTED',STATUS='OLD',IOSTAT=IOS)
IF (IOS .GT. 0) THEN
   WRITE(*,*) 'Problem opening input file ', TRIM(NAMELIST_FN)
   STOP
ENDIF

READ(LUINPUT,NML=RANK_RASTERS_INPUTS,END=100,IOSTAT=IOS)
 100  IF (IOS > 0) THEN
         WRITE(*,*) 'Error: Problem with namelist group &RANK_RASTERS_INPUTS.'
         STOP
      ENDIF
CLOSE(LUINPUT)

!Get operating system (linux or windows/dos)
CALL GET_OPERATING_SYSTEM

!Get coordinate system string
FN=TRIM(INPUT_DIRECTORY) // TRIM(RANKER_FILENAME_IN)
CALL GET_COORDINATE_SYSTEM(FN)

! Read in RANKER
CALL READ_BSQ_RASTER(RANKER, INPUT_DIRECTORY, RANKER_FILENAME_IN)
DO IRAS= 1, NRASTERS_TO_RANK
   CALL READ_BSQ_RASTER(RANKEE(IRAS), INPUT_DIRECTORY, RANKEE_FILENAME_IN(IRAS))
ENDDO
  
! Allocate arrays for sorting:
ALLOCATE(X(1:RANKER%NBANDS, 1:RANKER%NCOLS, 1:RANKER%NROWS))
ALLOCATE(Y(1:RANKER%NBANDS, 1:RANKER%NCOLS, 1:RANKER%NROWS))

!Now sort:
DO IRAS = 1, NRASTERS_TO_RANK
!$omp PARALLEL DO SCHEDULE(STATIC) PRIVATE(IROW,ICOL) SHARED(RANKEE,RANKER,X,Y,IRAS)
   DO IROW = 1, RANKER%NROWS
   DO ICOL = 1, RANKER%NCOLS
      X(:,ICOL,IROW) = RANKER%RZT      (:,ICOL,IROW)
      Y(:,ICOL,IROW) = RANKEE(IRAS)%RZT(:,ICOL,IROW)
      CALL DSORT (X(:,ICOL,IROW), Y(:,ICOL,IROW), RANKER%NBANDS, -2)
      IF (IRAS .EQ. NRASTERS_TO_RANK) RANKER%RZT(:,ICOL,IROW) = X(:,ICOL,IROW)
      RANKEE(IRAS)%RZT(:,ICOL,IROW) = Y(:,ICOL,IROW) 
   ENDDO
   ENDDO
!$omp END PARALLEL DO
ENDDO

! And write sorted rasters to disk:
IF (DUMP_SORTED_RASTERS) THEN
   DO IRAS = 1, NRASTERS_TO_RANK
      CALL WRITE_BIL_RASTER(RANKEE(IRAS), OUTPUT_DIRECTORY, RANKEE_FILENAME_OUT(IRAS), .TRUE., COMPRESS)
   ENDDO

   IF (DUMP_RANKER) CALL WRITE_BIL_RASTER(RANKER, OUTPUT_DIRECTORY, RANKER_FILENAME_OUT, .TRUE., COMPRESS)
ENDIF

IF (DUMP_PEAK_RASTERS) THEN
   CALL ALLOCATE_EMPTY_RASTER(PEAK,RANKER%NCOLS,RANKER%NROWS,1,RANKER%XLLCORNER,RANKER%YLLCORNER,RANKER%XDIM,RANKER%YDIM,RANKER%NODATA_VALUE,1,'FLOAT     ')

   DO IRAS = 1, NRASTERS_TO_RANK
      PEAK%RZT(1,:,:) = RANKEE(IRAS)%RZT(1,:,:)
      CALL WRITE_BIL_RASTER(PEAK, OUTPUT_DIRECTORY, RANKEE_PEAK_FILENAME_OUT(IRAS), .TRUE., COMPRESS)
   ENDDO

   IF (DUMP_RANKER) THEN
      PEAK%RZT(1,:,:) = RANKER%RZT(1,:,:)
      CALL WRITE_BIL_RASTER(PEAK, OUTPUT_DIRECTORY, RANKER_PEAK_FILENAME_OUT, .TRUE., COMPRESS)
   ENDIF
ENDIF

STOP

! *****************************************************************************
END PROGRAM RANK_RASTERS
! *****************************************************************************
