! *****************************************************************************
MODULE ELMFIRE_SPREAD_RATE
! *****************************************************************************

USE ELMFIRE_VARS

IMPLICIT NONE

CONTAINS

! *****************************************************************************
RECURSIVE SUBROUTINE SURFACE_SPREAD_RATE(L,DUMMY_NODE)
! *****************************************************************************
! Applies Rothermel suface fire spread model to calculate surface fire rate
! of spread, heat per unit area, fireline intensity, flame length, and 
! reaction intensity

TYPE (DLL), INTENT(INOUT) :: L
TYPE (NODE), POINTER, INTENT(INOUT) :: DUMMY_NODE
!Local variables:
INTEGER :: I, ILH, NUM_NODES
REAL :: WS_LIMIT, WSMF_LIMITED, PHIS_MAX, MOMEX2, MOMEX3, MEX_LIVE, M_DEAD, M_LIVE,ETAM_DEAD, ETAM_LIVE, &
        RHOBEPSQIG_DEAD, RHOBEPSQIG_LIVE, RHOBEPSQIG, IR_DEAD, IR_LIVE, MOMEX, SUM_MPRIMENUMER
REAL, DIMENSION(1:6) :: M, QIG, FEPSQIG, FMC, FMEX, MPRIMENUMER
TYPE (FUEL_MODEL_TABLE_TYPE) :: FMT
TYPE(NODE), POINTER :: C
REAL, PARAMETER :: BTUPFT2MIN_TO_KWPM2 = 1.055/(60. * 0.3048 * 0.3048)

IF (ASSOCIATED (DUMMY_NODE) ) THEN
   NUM_NODES = 1
   C => DUMMY_NODE
ELSE
   NUM_NODES = L%NUM_NODES
   C => L%HEAD
ENDIF

DO I = 1, NUM_NODES

   IF (USE_HAMADA .AND. C%IFBFM .EQ. 91) THEN
      C => C%NEXT
      CYCLE
   ENDIF

   M(1)  = C%M1
   M(2)  = C%M10
   M(3)  = C%M100
   M(4)  = C%M1 !Set dynamic dead to m1
   M(5)  = C%MLH
   M(6)  = C%MLW

   ILH = MAX(MIN(NINT(100.*M(5)),120),30)
   FMT=FUEL_MODEL_TABLE_2D(C%IFBFM,ILH)

!Calculate live fuel moisture of extinction:
   MPRIMENUMER(1:4) = FMT%WPRIMENUMER(1:4) * M(1:4)
   SUM_MPRIMENUMER=SUM(MPRIMENUMER(1:4))
   MEX_LIVE = FMT%MEX_LIVE * (1. - FMT%R_MPRIMEDENOME14SUM_MEX_DEAD * SUM_MPRIMENUMER ) - 0.226

   MEX_LIVE = MAX(MEX_LIVE, FMT%MEX_DEAD)
   FMEX(5:6) = FMT%F(5:6) * MEX_LIVE

   FMEX(1:4) = FMT%FMEX(1:4)

   FMC(:) = FMT%F(:) * M(:)

   QIG(:) = 250. + 1116.*M(:)

   FEPSQIG(:) = FMT%FEPS(:) * QIG(:)

   RHOBEPSQIG_DEAD = FMT%RHOB * SUM(FEPSQIG(1:4))
   RHOBEPSQIG_LIVE = FMT%RHOB * SUM(FEPSQIG(5:6))
   RHOBEPSQIG = FMT%F_DEAD * RHOBEPSQIG_DEAD + FMT%F_LIVE * RHOBEPSQIG_LIVE

   M_DEAD    = SUM(FMC(1:4))
   MOMEX     = M_DEAD / FMT%MEX_DEAD
   MOMEX2    = MOMEX * MOMEX
   MOMEX3    = MOMEX2 * MOMEX
   ETAM_DEAD = 1.0 - 2.59*MOMEX + 5.11*MOMEX2 - 3.52*MOMEX3
   ETAM_DEAD = MAX(0.,MIN(ETAM_DEAD,1.))
   IR_DEAD   = FMT%GP_WND_EMD_ES_HOC * ETAM_DEAD

   M_LIVE    = SUM(FMC(5:6))
   MOMEX     = M_LIVE / MEX_LIVE
   MOMEX2    = MOMEX * MOMEX
   MOMEX3    = MOMEX2 * MOMEX
   ETAM_LIVE = 1.0 - 2.59*MOMEX + 5.11*MOMEX2 - 3.52*MOMEX3
   ETAM_LIVE = MAX(0.,MIN(ETAM_LIVE,1.))
   IR_LIVE   = FMT%GP_WNL_EML_ES_HOC * ETAM_LIVE

   C%IR = IR_DEAD + IR_LIVE !Btu/(ft^2-min)

!   WS_LIMIT = 96.8*C%IR**0.3333333 !Andrews, Cruz, and Rothermel (2013) limit
   WS_LIMIT = 0.9*C%IR !Original limit
   WSMF_LIMITED = MIN(C%WSMF, WS_LIMIT)

!   WRITE(*,*) 'WSMF_LIMITED', WSMF_LIMITED
   C%PHIW_SURFACE = FMT%PHIWTERM * WSMF_LIMITED**FMT%B_COEFF

! Max slope factor is equal to max wind factor:
   PHIS_MAX = FMT%PHIWTERM * WS_LIMIT**FMT%B_COEFF
   C%PHIS_SURFACE = MIN(FMT%PHISTERM * C%TANSLP2, PHIS_MAX)

   C%VS0 = (C%ADJ + PERTURB_ADJ) * C%SUPPRESSION_ADJUSTMENT_FACTOR * DIURNAL_ADJUSTMENT_FACTOR * C%IR * FMT%XI / RHOBEPSQIG !ft/min
   C%VELOCITY_DMS_SURFACE = C%VS0 * (1.0 + C%PHIS_SURFACE + C%PHIW_SURFACE) !ft/min

! Convert reaction intensity to SI:
   C%IR           = C%IR * BTUPFT2MIN_TO_KWPM2 ! kW/m2
   C%HPUA_SURFACE = C%IR * FMT%TR * 60. ! kJ/m2
   C%FLIN_DMS_SURFACE = FMT%TR * C%IR * C%VELOCITY_DMS_SURFACE * 0.3048 ! kW/m

   C => C%NEXT
ENDDO

! *****************************************************************************
END SUBROUTINE SURFACE_SPREAD_RATE
! *****************************************************************************

! *****************************************************************************
RECURSIVE SUBROUTINE CROWN_SPREAD_RATE(L,DUMMY_NODE)
! *****************************************************************************

TYPE (DLL), INTENT(INOUT) :: L
TYPE (NODE), POINTER, INTENT(INOUT) :: DUMMY_NODE

INTEGER :: I, IX, IY, NUM_NODES
REAL :: WS10KMPH, CROSA, R0, CAC, FMCTERM, CBD_EFF, CBH_EFF, CROS, FLIN_SURFACE
TYPE(NODE), POINTER :: C
REAL, PARAMETER :: MPH_20FT_TO_KMPH_10M = 1.609 / 0.87 ! 1.609 km/h per mi/h; divide by 0.87 to go from 20 ft to 10 m
LOGICAL, PARAMETER :: USE_FLIN_DMS_SURFACE = .TRUE.

IF (ASSOCIATED (DUMMY_NODE) ) THEN
   NUM_NODES = 1
   C => DUMMY_NODE
ELSE
   NUM_NODES = L%NUM_NODES
   C => L%HEAD
ENDIF

DO I = 1, NUM_NODES
   IX=C%IX
   IY=C%IY

   IF (USE_FLIN_DMS_SURFACE) THEN
      FLIN_SURFACE=C%FLIN_DMS_SURFACE
   ELSE
      FLIN_SURFACE=C%FLIN_SURFACE
   ENDIF

   IF (C%VS0 .GT. 0. .AND. FLIN_SURFACE .GT. 0. .AND. CBD%R4(IX,IY,1) .GT. 1E-3 .AND. CC%R4(IX,IY,1) .GT. 1E-3) THEN 
      CROS = 0.

      IF (C%CRITICAL_FLIN .GT. 1E9) THEN
         C%HPUA_CANOPY = CBD%R4(IX,IY,1) * MAX(CH%R4(IX,IY,1) - CBH%R4(IX,IY,1),0.) * 12000. !kJ/m2
         IF (CBH%R4(IX,IY,1) .GE. 0.) THEN
            FMCTERM = 460. + 26. * C%FMC
            CBH_EFF = MAX(CBH%R4(IX,IY,1) + PERTURB_CBH, 0.1)
            C%CRITICAL_FLIN = (0.01 * CBH_EFF * FMCTERM) ** 1.5
         ELSE
            C%CRITICAL_FLIN = 9E9
         ENDIF
      ENDIF

      IF (FLIN_SURFACE .GT. C%CRITICAL_FLIN) THEN
         CBD_EFF  = MAX(CBD%R4(IX,IY,1) + PERTURB_CBD, 0.01)
         WS10KMPH = C%WS20_NOW * MPH_20FT_TO_KMPH_10M
         CROSA    = CROWN_FIRE_ADJ * 11.02 * WS10KMPH**0.9 * CBD_EFF**0.19 * EXP(-0.17*100.0*C%M1) / 0.3048 ! ft / min
         CROSA    = MIN(CROSA,CROWN_FIRE_SPREAD_RATE_LIMIT) ! ft/min
         R0       = (3.0 / CBD_EFF) / 0.3048 !ft/min
         CAC      = CROSA / R0

         IF (CAC .GT. 1) THEN !Active crown fire
            IF (CC%R4(IX,IY,1) .GE. CRITICAL_CANOPY_COVER) THEN 
               C%CROWN_FIRE = 2
               CROS = CROSA
               C%PHIW_CROWN = MIN(MAX(CROS / MAX(C%VS0, 0.001) - 1.0, 0.0), 200.0)
            ELSE
               C%CROWN_FIRE = 1
            ENDIF
         ELSE ! Passive crown fire
            C%CROWN_FIRE = 1
            IF (CC%R4(IX,IY,1) .GE. CRITICAL_CANOPY_COVER) THEN
               CROS = CROSA * EXP(-CAC)
               C%PHIW_CROWN = MIN(MAX(CROS / MAX(C%VS0,0.001) - 1.0, 0.0), 200.0)
            ENDIF
         ENDIF

      ENDIF ! FLIN_SURFACE .GT. C%CRITICAL_FLIN

   ENDIF ! CBD .GT. 1E-3 .AND. CC .GT. 1E-3
   C => C%NEXT
ENDDO ! I = 1, L%NUM_NODES

! *****************************************************************************
END SUBROUTINE CROWN_SPREAD_RATE
! *****************************************************************************

! *****************************************************************************
SUBROUTINE HAMADA(C)
! *****************************************************************************
! USE HAMADA MODEL TO CALCULATE THE ROS AT ANY WIND DIRECTION RELATIVE TO A GIVEN DIRECTION OF FIRE FRONT
! This subroutine is a contribution from Yiren Qin (yqin123@umd.edu)

TYPE(NODE), POINTER, INTENT(INOUT) :: C

REAL :: A_0 , D , F_B , V , X_T ! INPUTS 

! COEFFICIENT FOR HAMADA MODEL 
REAL, PARAMETER :: &
   C_14 = 1.6, C_24 = 0.1, C_34 = 0.007, C_44 = 25.0, C_54 = 2.5 , &
   C_1S = 1.0, C_2S = 0.0, C_3S = 0.005, C_4S = 5.0 , C_5S = 0.25, & 
   C_1U = 1.0, C_2U = 0.0, C_3U = 0.002, C_4U = 5.0 , C_5U = 0.2

REAL :: CV_4 , CV_S , CV_U 
REAL :: K_D , K_S , K_U, K_D_C , K_S_C , K_U_C , T_4 , T_S , T_U , & 
        V_D , V_D_C , V_S , V_S_C , V_U , V_U_C 

! HAMADA ELLIPSE DEFINITION 
X_T = 120.0      ! TIME IN MINUTES, the ROS predicted by Hamada model is a function of time, but will converge to a constant value in short. 
V   = C%WS20_NOW * 0.447 ! WIND SPEED , M / S 

! These values are taken at constant at this stage, but should vary with the footprint.
!A_0 = 23        ! AVERAGE BUILDING PLAN DIMENSION , M 
!D   = 45         ! AVERAGE BUILDING SEPERATION , M 
!F_B = 0       ! RATIO OF FIRE RESISTANCE BUILDINGS

A_0 = HAMADA_A%R4 (C%IX,C%IY,1) ! AVERAGE BUILDING PLAN DIMENSION , M 
D   = HAMADA_D%R4 (C%IX,C%IY,1) ! AVERAGE BUILDING SEPERATION , M 
F_B = HAMADA_FB%R4(C%IX,C%IY,1) ! RATIO OF FIRE RESISTANCE BUILDINGS

CV_4 = C_14 * ( 1 + C_24 * V + C_34 * V ** 2 ) 
CV_S = C_1S * ( 1 + C_2S * V + C_3S * V ** 2 ) 
CV_U = C_1U * ( 1 + C_2U * V + C_3U * V ** 2 ) 

! TIME IN MINUTES THE FULLY DEVELOPED FIRE REQUIRES TO ADVANCE TO THE NEXT BUILDING 
T_4 = (( 1-F_B ) * ( 3 + 0.375 * A_0 + ( 8 * D / ( C_44 + C_54 * V ) ) ) + & 
      F_B * ( 5 + 0.625 * A_0 + 16 * D / ( C_44 + C_54 * V ) ) )/ CV_4 
T_S = (( 1-F_B ) * ( 3 + 0.375 * A_0 + ( 8 * D / ( C_4S + C_5S * V ) ) ) + & 
      F_B * ( 5 + 0.625 * A_0 + 16 * D / ( C_4S + C_5S * V ) )) / CV_S 
T_U = (( 1-F_B ) * ( 3 + 0.375 * A_0 + ( 8 * D / ( C_4U + C_5U * V ) ) ) + & 
      F_B * ( 5 + 0.625 * A_0 + 16 * D / ( C_4U + C_5U * V ) ) )/ CV_U 

K_D = MAX(( A_0 + D ) / T_4 * X_T ,1E-10)
K_S = MAX(( A_0 / 2 + D ) + ( A_0 + D ) / T_S * ( X_T-T_S ),1E-10) 
K_U = MAX(( A_0 / 2 + D ) + ( A_0 + D ) / T_U * ( X_T-T_U ),1E-10)

V_D = MAX(( A_0 + D ) / T_4,1E-10) 
V_S = MAX(( A_0 + D ) / T_S,1E-10) 
V_U = MAX(( A_0 + D ) / T_U,1E-10)

! HAZUS CORRECTION
IF(V .LE. 10) THEN

   K_D_C = K_D * V/10.0+SQRT((K_D+K_U)/2*K_S)*(1-V/10.0)
   K_U_C = K_U * V/10.0+SQRT((K_D+K_U)/2*K_S)*(1-V/10.0)
   K_S_C = K_S * V/10.0+SQRT((K_D+K_U)/2*K_S)*(1-V/10.0)
   
   V_D_C = MAX(V_D * V / 10 + & 
            ( K_D * V_S + V_D * K_S + K_U * V_S + V_U * K_S ) * & 
           SQRT( 2 / ( K_D + K_U )/K_S ) * ( 1-V / 10 )/4,1E-10)
   V_S_C = MAX(V_S * V / 10 + & 
            ( K_D * V_S + V_D * K_S + K_U * V_S + V_U * K_S ) * & 
           SQRT( 2 / ( K_D + K_U )/K_S ) * ( 1-V / 10 )/4,1E-10)
   V_U_C = MAX(V_U * V / 10 + & 
            ( K_D * V_S + V_D * K_S + K_U * V_S + V_U * K_S ) * & 
           SQRT( 2 / ( K_D + K_U )/K_S ) * ( 1-V / 10 )/4 ,1E-10)

   V_D = V_D_C !M/MIN
   V_S = V_S_C !M/MIN
   V_U = V_U_C !M/MIN
ENDIF

IF(MIN(K_D,MIN(K_S,K_U)) .LE. 1E-1) THEN
    V_D = K_D/MAX(X_T,1E-10)
    V_S = K_S/MAX(X_T,1E-10)
    V_U = K_U/MAX(X_T,1E-10)
ENDIF

C%VELOCITY_DMS = V_D /0.3048 ! Unit Transform to ft/min
C%VBACK = V_U/0.3048
C%LOW = MIN((V_D+V_U)/2/V_S,10.0)
! OPEN(19971205, FILE="HAMADA_DIAGNOSTIC.csv")
! WRITE(19971205,*) K_D, K_S, K_U,V_D, V_S, V_U

! *****************************************************************************
END SUBROUTINE HAMADA
! *****************************************************************************

END MODULE