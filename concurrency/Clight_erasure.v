Require Import compcert.common.Memory.


Require Import veric.compcert_rmaps.
Require Import veric.juicy_mem.
Require Import veric.res_predicates.

(*IM using proof irrelevance!*)
Require Import ProofIrrelevance.

(* The concurrent machinery*)
Require Import concurrency.scheduler.
Require Import concurrency.concurrent_machine.
Require Import concurrency.juicy_machine. Import Concur.
Require Import concurrency.dry_machine. Import Concur.
(*Require Import concurrency.dry_machine_lemmas. *)
Require Import concurrency.lksize.
Require Import concurrency.permissions.

(*The simulations*)
Require Import sepcomp.wholeprog_simulations.

(*General erasure*)
Require Import concurrency.erasure.

From mathcomp.ssreflect Require Import ssreflect seq.

Import addressFiniteMap.

(* I will import this from CLight once we port it*)
(*Module ClightSEM<: Semantics.
  Definition G:= nat.
  Definition C:= nat.
  Definition M:= Mem.mem.
  Definition  
End ClightSEM.*)

Module ClightParching <: ErasureSig.

  Declare Module ClightSEM: Semantics. (*This will be imported from Clight wonce we port it*)
  Module SCH:= ListScheduler NatTID.            
  Module SEM:= ClightSEM.
  Import SCH SEM.

  Module JSEM:= JuicyMachineShell SEM. (* JuicyMachineShell : Semantics -> ConcurrentSemanticsSig *)
  Module JuicyMachine:= CoarseMachine SCH JSEM. (* CoarseMachine : Schedule -> ConcurrentSemanticsSig -> ConcurrentSemantics *)
  Notation JMachineSem:= JuicyMachine.MachineSemantics.
  Notation jstate:= JuicyMachine.SIG.ThreadPool.t.
  Notation jmachine_state:= JuicyMachine.MachState.
  Module JTP:=JuicyMachine.SIG.ThreadPool.
  Import JSEM.JuicyMachineLemmas.

  Search JSEM.mem_compatible.
  
  Module DSEM:= DryMachineShell SEM.
  Module DryMachine:= CoarseMachine SCH DSEM.
  Notation DMachineSem:= DryMachine.MachineSemantics. 
  Notation dstate:= DryMachine.SIG.ThreadPool.t.
  Notation dmachine_state:= DryMachine.MachState.
  Module DTP:=DryMachine.SIG.ThreadPool.
  Import DSEM.DryMachineLemmas.



  (** * Match relation between juicy and dry state : *)
  (* 1/2. Same threads are contained in each state: 
     3.   Threads have the same c 
     4.   Threads have the same permissions up to erasure 
     5.   the locks are in the same addresses. 
     6/7. Lock contents match up to erasure. *)
  Inductive match_st' : jstate ->  dstate -> Prop:=
    MATCH_ST: forall (js:jstate) ds
                (mtch_cnt: forall {tid},  JTP.containsThread js tid -> DTP.containsThread ds tid )
                (mtch_cnt': forall {tid}, DTP.containsThread ds tid -> JTP.containsThread js tid )
                (mtch_gtc: forall {tid} (Htid:JTP.containsThread js tid)(Htid':DTP.containsThread ds tid),
                    JTP.getThreadC Htid = DTP.getThreadC Htid' )
                (mtch_perm: forall b ofs {tid} (Htid:JTP.containsThread js tid)(Htid':DTP.containsThread ds tid),
                    juicy_mem.perm_of_res (resource_at (JTP.getThreadR Htid) (b, ofs)) = ((DTP.getThreadR Htid') !! b) ofs )
                (mtch_locks: forall a,
                    ssrbool.isSome (JSEM.ThreadPool.lockRes js a) = ssrbool.isSome (DSEM.ThreadPool.lockRes ds a))
                (mtch_locksEmpty: forall lock dres,
                    JSEM.ThreadPool.lockRes js lock = Some (None) -> 
                    DSEM.ThreadPool.lockRes ds lock = Some dres ->
                   dres = empty_map )
                (mtch_locksRes: forall lock jres dres,
                    JSEM.ThreadPool.lockRes js lock = Some (Some jres) -> 
                    DSEM.ThreadPool.lockRes ds lock = Some dres ->
                     forall b ofs,
                    juicy_mem.perm_of_res (resource_at jres (b, ofs)) = (dres !! b) ofs )
                (*mtch_locks: AMap.map (fun _ => tt) (JTP.lockGuts js) = DTP.lockGuts ds*),
      match_st' js ds.
  Definition match_st:= match_st'.

  
  (** *Match lemmas*)
  Lemma MTCH_cnt: forall {js tid ds},
           match_st js ds ->
           JTP.containsThread js tid -> DTP.containsThread ds tid.
  Proof. intros ? ? ? MTCH. inversion MTCH. apply mtch_cnt. Qed.
  Lemma MTCH_cnt': forall {js tid ds},
           match_st js ds ->
           DTP.containsThread ds tid -> JTP.containsThread js tid.
  Proof. intros ? ? ? MTCH. inversion MTCH. apply mtch_cnt'. Qed.


  Lemma cnt_irr: forall tid ds (cnt1 cnt2: DTP.containsThread ds tid),
      DTP.getThreadC cnt1 = DTP.getThreadC cnt2.
  Proof. intros.
         
         unfold DTP.getThreadC.
         destruct ds; simpl.
         f_equal; f_equal.
         eapply proof_irrelevance.
  Qed.

  Lemma MTCH_getThreadC: forall js ds tid c,
      forall (cnt: JTP.containsThread js tid)
        (cnt': DTP.containsThread ds tid)
        (M: match_st js ds),
        JTP.getThreadC cnt =  c ->
        DTP.getThreadC cnt'  =  c.
  Proof. intros ? ? ? ? ? MTCH; inversion MTCH; subst.
         intros HH; inversion HH; subst.
         intros AA; rewrite <- AA. symmetry; apply mtch_gtc.
  Qed.
       
  Lemma MTCH_compat: forall js ds m,
      match_st js ds ->
      JSEM.mem_compatible js m ->
      DSEM.mem_compatible ds m.
  Proof. 
    intros ? ? ? MTCH mc;
    inversion MTCH; subst.
    constructor.
    -intros tid cnt.
     unfold permMapLt; intros b ofs.
     assert (th_coh:= JSEM.thread_mem_compatible mc).
     eapply po_trans.
     specialize (th_coh tid (mtch_cnt' _ cnt)).
     inversion th_coh.
     specialize (acc_coh (b, ofs)).
     rewrite getMaxPerm_correct;
       apply acc_coh.
     
     rewrite (mtch_perm _ _ _ (mtch_cnt' tid cnt) cnt).
     unfold DTP.getThreadR.
     apply po_refl.

    - intros.
      assert(HH: exists jres, JSEM.ThreadPool.lockRes js l = Some jres).
      { specialize (mtch_locks  l); rewrite H in mtch_locks.
      destruct (JSEM.ThreadPool.lockRes js l); try solve[inversion mtch_locks].
      exists l0; reflexivity. }
      destruct HH as [jres HH].
      destruct jres.
      +  specialize (mtch_locksRes _ _ _ HH H).
         intros b ofs.
         rewrite <- mtch_locksRes.
         eapply JSEM.compat_lockLT;
           eassumption.
      + specialize (mtch_locksEmpty _ _ HH H).
         rewrite mtch_locksEmpty.
         apply empty_LT.
    - intros b ofs.
      rewrite DSEM.ThreadPool.lockSet_spec.
      rewrite <- mtch_locks.
      rewrite <- JSEM.ThreadPool.lockSet_spec.
      apply JSEM.compat_lt_m; assumption.
  Qed.
  
  Lemma MTCH_updt:
    forall js ds tid c
      (H0:match_st js ds)
      (cnt: JTP.containsThread js tid)
      (cnt': DTP.containsThread ds tid),
      match_st (JTP.updThreadC cnt c)
               (DTP.updThreadC cnt' c).
  Proof.
    intros. constructor; intros.
    - apply DTP.cntUpdateC.
      inversion H0; subst.
      apply mtch_cnt.
      eapply JTP.cntUpdateC'; apply H.
    - apply JTP.cntUpdateC.
      inversion H0; subst.
      apply mtch_cnt'.
        eapply DTP.cntUpdateC'; apply H.
    - destruct (NatTID.eq_tid_dec tid tid0) as [e|ine].
      + subst.
          rewrite JTP.gssThreadCC;
          rewrite DTP.gssThreadCC.
          reflexivity.
      + assert (cnt2:= JTP.cntUpdateC' _ cnt Htid).
        rewrite <- (JTP.gsoThreadCC ine cnt cnt2 c Htid) by assumption.
        inversion H0; subst.
          (* pose (cnt':=(@MTCH_cnt js tid ds H0 cnt)). *)
          assert (cnt2':= DTP.cntUpdateC' _ cnt' Htid').
          (*fold cnt';*)
          rewrite <- (DTP.gsoThreadCC ine cnt' cnt2' c Htid') by assumption.
          apply mtch_gtc; assumption.
      - inversion H0; apply mtch_perm.
      - inversion H0; apply mtch_locks.
      - inversion H0; eapply mtch_locksEmpty; eauto.
      - inversion H0; eapply mtch_locksRes; eauto.
    Qed.
    
    Lemma MTCH_restrict_personal:
      forall ds js m i
        (MTCH: match_st js ds)
        (Hi: JTP.containsThread js i)
        (Hi': DTP.containsThread ds i)
        (Hcmpt: JSEM.mem_compatible js m)
        (Hcmpt': DSEM.mem_compatible ds m),
        restrPermMap (DSEM.compat_th Hcmpt' Hi') =
        m_dry (JSEM.personal_mem Hi Hcmpt).
    Proof.
      intros.
      inversion MTCH; subst.
      unfold JSEM.personal_mem; simpl; unfold JSEM.juicyRestrict; simpl.
      apply restrPermMap_ext; intros.
      extensionality ofs;
        erewrite <- mtch_perm.
      instantiate(1:=Hi).
      erewrite JSEM.juic2Perm_correct. reflexivity.
      destruct (@JSEM.thread_mem_compatible _ _ Hcmpt _ Hi); assumption.
    Qed.
      
    Lemma MTCH_halted:
      forall ds js i
        (cnt: JTP.containsThread  js i)
        (cnt': DTP.containsThread  ds i),
        match_st js ds->
        JSEM.threadHalted cnt ->
        DSEM.invariant ds ->
        DSEM.threadHalted cnt'.
    Proof.
      intros.
      inversion H0; subst.
      econstructor.
      - assumption.
      - inversion H; subst. erewrite <- mtch_gtc. eassumption.
      - apply Hcant.
    Qed.
    
    Lemma MTCH_updLockS:
             forall js ds loc jres dres,
               match_st js ds ->
             (forall b ofs, perm_of_res (jres @ (b, ofs)) = dres !! b ofs) ->
                      match_st
                        (JSEM.ThreadPool.updLockSet js loc (Some jres))
                        (DSEM.ThreadPool.updLockSet ds loc dres).
    Proof. intros.
           constructor.
           + intros. apply DTP.cntUpdateL.
             destruct H; apply mtch_cnt.
             apply JTP.cntUpdateL' in H1; assumption.
           + intros. apply JTP.cntUpdateL.
             destruct H; apply mtch_cnt'.
             apply DTP.cntUpdateL' in H1; assumption.
           + intros. rewrite JSEM.ThreadPool.gLockSetCode DSEM.ThreadPool.gLockSetCode.
             inversion H; subst. apply mtch_gtc. 
           + intros. rewrite JSEM.ThreadPool.gLockSetRes DSEM.ThreadPool.gLockSetRes.
             inversion H; subst. apply mtch_perm.
           + intros.
             destruct (AMap.E.eq_dec loc a) as [EQ | NEQ].
             * subst loc. rewrite JSEM.ThreadPool.gsslockResUpdLock DSEM.ThreadPool.gsslockResUpdLock.
               reflexivity.
             * rewrite JSEM.ThreadPool.gsolockResUpdLock DSEM.ThreadPool.gsolockResUpdLock.
               inversion H. solve[apply mtch_locks].
           + intros. 
             destruct (AMap.E.eq_dec loc lock) as [EQ | NEQ].
             * subst loc. rewrite JSEM.ThreadPool.gsslockResUpdLock in H1; inversion H1. 
             * rewrite JSEM.ThreadPool.gsolockResUpdLock in H1. rewrite DSEM.ThreadPool.gsolockResUpdLock in H2.
               inversion H. eapply mtch_locksEmpty; eassumption.
           + intros. 
             destruct (AMap.E.eq_dec loc lock) as [EQ | NEQ].
             * subst loc.
               rewrite JSEM.ThreadPool.gsslockResUpdLock in H1.
               rewrite DSEM.ThreadPool.gsslockResUpdLock in H2.
               inversion H1; inversion H2; subst.
               apply H0.
             * rewrite JSEM.ThreadPool.gsolockResUpdLock in H1. rewrite DSEM.ThreadPool.gsolockResUpdLock in H2.
               inversion H. eapply mtch_locksRes; eassumption.
    Qed.
    
    Lemma MTCH_updLockN:
      forall js ds loc,
        match_st js ds ->
        match_st
          (JSEM.ThreadPool.updLockSet js loc None)
          (DSEM.ThreadPool.updLockSet ds loc empty_map).
           intros.
           constructor.
           + intros. apply DTP.cntUpdateL.
             destruct H; apply mtch_cnt.
             apply JTP.cntUpdateL' in H0; assumption.
           + intros. apply JTP.cntUpdateL.
             destruct H; apply mtch_cnt'.
             apply DTP.cntUpdateL' in H0; assumption.
           + intros. rewrite JSEM.ThreadPool.gLockSetCode DSEM.ThreadPool.gLockSetCode.
             inversion H; subst. apply mtch_gtc. 
           + intros. rewrite JSEM.ThreadPool.gLockSetRes DSEM.ThreadPool.gLockSetRes.
             inversion H; subst. apply mtch_perm.
           + intros.
             destruct (AMap.E.eq_dec loc a) as [EQ | NEQ].
             * subst loc. rewrite JSEM.ThreadPool.gsslockResUpdLock DSEM.ThreadPool.gsslockResUpdLock.
               reflexivity.
             * rewrite JSEM.ThreadPool.gsolockResUpdLock DSEM.ThreadPool.gsolockResUpdLock.
               inversion H. solve[apply mtch_locks].
           + intros. 
             destruct (AMap.E.eq_dec loc lock) as [EQ | NEQ].
             * subst loc. rewrite DSEM.ThreadPool.gsslockResUpdLock in H1; inversion H1; reflexivity. 
             * rewrite DSEM.ThreadPool.gsolockResUpdLock in H1.
               rewrite JSEM.ThreadPool.gsolockResUpdLock in H0.
               inversion H. eapply mtch_locksEmpty; eassumption.
           + intros. 
             destruct (AMap.E.eq_dec loc lock) as [EQ | NEQ].
             * subst loc.
               rewrite JSEM.ThreadPool.gsslockResUpdLock in H0.
               rewrite DSEM.ThreadPool.gsslockResUpdLock in H1.
               inversion H0. 
             * rewrite JSEM.ThreadPool.gsolockResUpdLock in H0. rewrite DSEM.ThreadPool.gsolockResUpdLock in H1.
               inversion H. eapply mtch_locksRes; eassumption.
    Qed.
    
    Lemma MTCH_remLockN:
      forall js ds loc,
        match_st js ds ->
        match_st
          (JSEM.ThreadPool.remLockSet js loc)
          (DSEM.ThreadPool.remLockSet ds loc).
           intros.
           constructor.
           + intros. apply DTP.cntRemoveL.
             destruct H; apply mtch_cnt.
             apply JTP.cntRemoveL' in H0; assumption.
           + intros. apply JTP.cntRemoveL.
             destruct H; apply mtch_cnt'.
             apply DTP.cntRemoveL' in H0; assumption.
           + intros. rewrite JSEM.ThreadPool.gRemLockSetCode DSEM.ThreadPool.gRemLockSetCode.
             inversion H; subst. apply mtch_gtc. 
           + intros. rewrite JSEM.ThreadPool.gRemLockSetRes  DSEM.ThreadPool.gRemLockSetRes.
             inversion H; subst. apply mtch_perm.
           + intros.
             destruct (AMap.E.eq_dec loc a) as [EQ | NEQ].
             * subst loc. rewrite JSEM.ThreadPool.gsslockResRemLock DSEM.ThreadPool.gsslockResRemLock.
               reflexivity.
             * rewrite JSEM.ThreadPool.gsolockResRemLock DSEM.ThreadPool.gsolockResRemLock.
               inversion H. solve[apply mtch_locks].
           + intros. 
             destruct (AMap.E.eq_dec loc lock) as [EQ | NEQ].
             * subst loc. rewrite DSEM.ThreadPool.gsslockResRemLock in H1; inversion H1; reflexivity. 
             * rewrite DSEM.ThreadPool.gsolockResRemLock in H1.
               rewrite JSEM.ThreadPool.gsolockResRemLock in H0.
               inversion H. eapply mtch_locksEmpty; eassumption.
           + intros. 
             destruct (AMap.E.eq_dec loc lock) as [EQ | NEQ].
             * subst loc.
               rewrite JSEM.ThreadPool.gsslockResRemLock in H0.
               rewrite DSEM.ThreadPool.gsslockResRemLock in H1.
               inversion H0. 
             * rewrite JSEM.ThreadPool.gsolockResRemLock in H0. rewrite DSEM.ThreadPool.gsolockResRemLock in H1.
               inversion H. eapply mtch_locksRes; eassumption.
    Qed.
    
    Lemma MTCH_update:
      forall js ds Kc phi p i
        (Hi : JTP.containsThread js i)
        (Hi': DTP.containsThread ds i),
        match_st js ds ->
        ( forall b ofs,
            perm_of_res (phi @ (b, ofs)) = p !! b ofs) -> 
        match_st (JSEM.ThreadPool.updThread Hi  Kc phi)
                 (DSEM.ThreadPool.updThread Hi' Kc p).
    Proof.
      intros. inversion H; subst.
      constructor; intros.
      - apply DTP.cntUpdate. apply mtch_cnt.
        eapply JTP.cntUpdate'; eassumption.
      - apply JTP.cntUpdate. apply mtch_cnt'.
        eapply DTP.cntUpdate'; eassumption.
      - destruct (NatTID.eq_tid_dec i tid).
        + subst.
          rewrite JTP.gssThreadCode DTP.gssThreadCode; reflexivity.
        + assert (jcnt2:= JTP.cntUpdateC' Kc Hi Htid).
          assert (dcnt2:= DTP.cntUpdateC' Kc Hi' Htid').
          rewrite (JTP.gsoThreadCode n Hi  jcnt2 _ _ Htid); auto.
          rewrite (DTP.gsoThreadCode n Hi' dcnt2 _ _  Htid'); auto.
      - destruct (NatTID.eq_tid_dec i tid).
        + subst.
          rewrite (JTP.gssThreadRes Hi _ _ Htid); auto.
          rewrite (DTP.gssThreadRes Hi'  _ _  Htid'); auto.
        + assert (jcnt2:= JTP.cntUpdateC' Kc Hi Htid).
          assert (dcnt2:= DTP.cntUpdateC' Kc Hi' Htid').
          rewrite (JTP.gsoThreadRes Hi jcnt2 n _ _ Htid); auto.
          rewrite (DTP.gsoThreadRes Hi' dcnt2 n _ _  Htid'); auto.
      - simpl; apply mtch_locks.
      - simpl. eapply mtch_locksEmpty; eassumption.
      - simpl; eapply mtch_locksRes; eassumption.
    Qed.

    Lemma MTCH_initial:
      forall genv c,
        match_st (JSEM.initial_machine c) (DSEM.initial_machine genv c).
    Proof.
      intros.
      constructor.
      - intro i. unfold JTP.containsThread, JSEM.initial_machine; simpl.
        unfold DTP.containsThread, DSEM.initial_machine; simpl.
        trivial.
      - intro i. unfold JTP.containsThread, JSEM.initial_machine; simpl.
        unfold DTP.containsThread, DSEM.initial_machine; simpl.
        trivial.
      - reflexivity.
      - intros.
        unfold JTP.getThreadR; unfold JSEM.initial_machine; simpl.
        unfold DTP.getThreadR; unfold DSEM.initial_machine; simpl.
        unfold empty_rmap, "@"; simpl.
        rewrite compcert_rmaps.R.unsquash_squash; simpl.
        destruct (eq_dec Share.bot Share.bot); try solve[exfalso; apply n; reflexivity].
        unfold DSEM.compute_init_perm.
        rewrite empty_map_spec; reflexivity.
      - reflexivity.
      - unfold DSEM.ThreadPool.lockRes, DSEM.initial_machine; simpl.
        intros. rewrite threadPool.find_empty in H0; inversion H0.
      - unfold DSEM.ThreadPool.lockRes, DSEM.initial_machine; simpl.
        intros. rewrite threadPool.find_empty in H0; inversion H0.
    Qed.
    
    Variable genv: G.
    Variable main: Values.val.
    Lemma init_diagram:
      forall (j : Values.Val.meminj) (U:schedule) (js : jstate)
        (vals : list Values.val) (m : mem),
        init_inj_ok j m ->
        initial_core (JMachineSem U) genv main vals = Some (U, js) ->
        exists (mu : SM_Injection) (ds : dstate),
          as_inj mu = j /\
          initial_core (DMachineSem U) genv main vals = Some (U, ds) /\
          DSEM.invariant ds /\
          match_st js ds.
    Proof.
      intros.

      (* Build the structured injection*)
      exists (initial_SM (valid_block_dec m) (valid_block_dec m) (fun _ => false) (fun _ => false) j).

      (* Build the dry state *)
      simpl in H0.
      unfold JuicyMachine.init_machine in H0.
      unfold JSEM.init_mach in H0. simpl in H0.
      destruct ( initial_core JSEM.ThreadPool.SEM.Sem genv main vals) eqn:C; try solve[inversion H0].
      inversion H0.
      exists (DSEM.initial_machine genv c).

      split; [|split;[|split]].
      
      (*Proofs*)
      - apply initial_SM_as_inj.
      - simpl.
        unfold DryMachine.init_machine.
        unfold DSEM.init_mach.
        rewrite C.
        f_equal.
      - apply initial_invariant.
      - apply MTCH_initial.
    Qed.
  
  Lemma conc_step_diagram:
    forall m m' U js js' ds i genv
      (MATCH: match_st js ds)
      (dinv: DSEM.invariant ds)
      (Hi: JSEM.ThreadPool.containsThread js i)
      (Hcmpt: JSEM.mem_compatible js m)
      (HschedN: schedPeek U = Some i)
      (Htstep:  JSEM.syncStep genv Hi Hcmpt js' m'),
      exists ds' : dstate,
        DSEM.invariant ds' /\
        match_st js' ds' /\
        DSEM.syncStep genv (MTCH_cnt MATCH Hi) (MTCH_compat _ _ _ MATCH Hcmpt) ds' m'.
  Proof.

    intros.
    inversion Htstep; try subst.
    
    (* step_acquire  *)
    {
    assert (Htid':= MTCH_cnt MATCH Hi).
    pose (inflated_delta:=
            fun loc => match (d_phi @ loc ) with
                      NO s => if Share.EqDec_share s Share.bot then None else Some ( perm_of_res ((m_phi jm') @ loc))
                    | _ => Some (perm_of_res ((m_phi jm') @ loc))
                    end).
         pose (virtue:= PTree.map
                                      (fun (block : positive) (_ : Z -> option permission) (ofs : Z) =>
                                         (inflated_delta (block, ofs))) (snd (getCurPerm m)) ).
         assert (virtue_some: forall l p, inflated_delta l = Some p ->
                             p = perm_of_res (m_phi jm' @ l)).
            {
              intros l p; unfold inflated_delta.
              destruct (d_phi @ l); try solve[intros HH; inversion HH; reflexivity].
              destruct ( proj_sumbool (Share.EqDec_share t Share.bot));
                [congruence| intros HH; inversion HH; reflexivity]. }
            
         pose (ds':= DSEM.ThreadPool.updThread Htid' (Kresume c Vundef)
                  (computeMap
                     (DSEM.ThreadPool.getThreadR Htid') virtue)).
         pose (ds'':= DSEM.ThreadPool.updLockSet ds'
                      (b, Int.intval ofs) empty_map).
         exists ds''.
         split; [|split].
    - unfold ds''.
      rewrite DSEM.ThreadPool.updLock_updThread_comm.
      pose (ds0:= (DSEM.ThreadPool.updLockSet ds (b, (Int.intval ofs)) empty_map)).
      
      cut (DSEM.invariant ds0).
      { (* Proving: invariant ds0' *)
        intros dinv0.
        apply updThread_inv.
        - assumption.
        - Inductive deltaMap_cases (dmap:delta_map) b ofs:=
        | DMAPS df p:  dmap ! b = Some df -> df ofs = Some p -> deltaMap_cases dmap b ofs
        | DNONE1 df:  dmap ! b = Some df -> df ofs = None -> deltaMap_cases dmap b ofs
        | DNONE2:  dmap ! b = None -> deltaMap_cases dmap b ofs.
          Lemma deltaMap_dec: forall dmap b ofs, deltaMap_cases dmap b ofs.
          Proof. intros. destruct (dmap ! b) eqn:H1; [destruct (o ofs) eqn:H2 | ]; econstructor; eassumption. Qed.

          Definition deltaMap_cases_analysis dmap b ofs H1 H2 H3 :Prop:=
            match deltaMap_dec dmap b ofs with
              | DMAPS df p A B => H1 df p A B
              | DNONE1 df A B => H2 df A B
              | DNONE2 A => H3 A 
            end.

          Definition deltaMap_cases_analysis' dmap b ofs H1 H2 :Prop:=
            match deltaMap_dec dmap b ofs with
              | DMAPS df p A B => H1 df p
              | DNONE1 df A B => H2
              | DNONE2 A => H2 
            end.
          
          Lemma Disjoint_computeMap: forall pmap1 pmap2 dmap,
              (forall b ofs,
                deltaMap_cases_analysis' dmap b ofs (fun _ p => permDisjoint p (pmap2 !! b ofs)) (permDisjoint (pmap1 !! b ofs) (pmap2 !! b ofs))) ->
              permMapsDisjoint (computeMap pmap1 dmap) pmap2.
          Proof.
            intros. intros b0 ofs0.
            generalize (H b0 ofs0); clear H; unfold deltaMap_cases_analysis'.
            destruct (deltaMap_dec dmap b0 ofs0); intros H.
            -  rewrite (computeMap_1 _ _ _ _ e e0).
               destruct H as [k H3].
               exists k; assumption.
            - rewrite (computeMap_2 _ _ _ _ e e0).
               destruct H as [k H3].
               exists k; assumption.
            - rewrite (computeMap_3 _ _ _ _ e).
               destruct H as [k H3].
               exists k; assumption.
          Qed.
               
          (*virtue is disjoint from other threads. *)
          intros. rewrite DTP.gLockSetRes.
          apply Disjoint_computeMap. intros. 
          unfold deltaMap_cases_analysis'; destruct (deltaMap_dec virtue b0 ofs0).
          + unfold virtue in e.
            rewrite PTree.gmap in e. destruct ((snd (getCurPerm m)) ! b0); inversion e.
            clear e. rewrite <- H1 in e0.
            
            rewrite (virtue_some _ _ e0).
            inversion MATCH. rewrite <- mtch_perm with (Htid:= mtch_cnt' _ cnt).
            apply join_permDisjoint.
            Lemma triple_joins_exists:
              forall (a b c ab: rmap),
                sepalg.join a b ab ->
                joins b c ->
                joins a c ->
                joins ab c.
            Proof.
              intros a b c ab Hab [bc Hbc] [ac Hac].
              destruct (triple_join_exists a b c ab bc ac Hab Hbc Hac).
              exists x; assumption.
            Qed.
            Lemma resource_at_joins:
              forall r1 r2,
                joins r1 r2 ->
                forall l,
                  joins (r1 @ l) (r2 @ l).
            Proof. intros r1 r2 [r3 HH] l.
                   exists (r3 @l); apply resource_at_join. assumption.
            Qed.

            apply resource_at_joins.
            eapply triple_joins_exists.
            eassumption.
            { eapply joins_comm. eapply compatible_threadRes_lockRes_join.
              eassumption.
              apply His_unlocked.
            }
            { eapply compatible_threadRes_join.
              eassumption.
              assumption.
            }
          + inversion dinv0; eapply no_race; assumption.
          + inversion dinv0; eapply no_race; assumption.
        - apply permMapsDisjoint_comm.
          apply Disjoint_computeMap. intros b0 ofs0. 
          unfold deltaMap_cases_analysis'; destruct (deltaMap_dec virtue b0 ofs0).
          + unfold virtue in e.
            rewrite PTree.gmap in e. destruct ((snd (getCurPerm m)) ! b0); inversion e.
            clear e. rewrite <- H0 in e0.
            rewrite (virtue_some _ _ e0).
            inversion MATCH.
            destruct (AMap.E.eq_dec (b, Int.intval ofs)(b0, ofs0)).
            * inversion e; simpl; subst.
              rewrite DSEM.ThreadPool.lockSet_spec.
              rewrite DTP.gssLockRes; simpl.
              apply (resource_at_join _ _ _ (b0, Int.intval ofs)) in 
                  Hadd_lock_res.
              rewrite HJcanwrite in Hadd_lock_res.
              Lemma join_lock:
                forall {sh psh n R r1 r2},
                  sepalg.join (YES sh psh (LK n) R) r1 r2 ->
                  perm_of_res r2 = Some Nonempty.
              Proof. intros. inversion H; reflexivity. Qed.
              rewrite (join_lock Hadd_lock_res).
              exists ((Some Writable)); reflexivity.
            * rewrite DTP.gsoLockSet; try assumption.
              admit. (*Must change mem_compatible:
                       Add a clause stating the converse of locks_correct. In short
                       that something in lockSet must be a lock in some thread. *)
            
          + inversion dinv0; apply permDisjoint_comm;
            eapply lock_set_threads.     
          + inversion dinv0; apply permDisjoint_comm;
            eapply lock_set_threads.
        - intros l pmap0 Lres. apply permMapsDisjoint_comm.
          apply Disjoint_computeMap. intros b0 ofs0. 
          unfold deltaMap_cases_analysis'; destruct (deltaMap_dec virtue b0 ofs0).
          + unfold virtue in e.
            rewrite PTree.gmap in e. destruct ((snd (getCurPerm m)) ! b0); inversion e.
            clear e. rewrite <- H0 in e0.
            rewrite (virtue_some _ _ e0).
            destruct (AMap.E.eq_dec (b, Int.intval ofs) l).
            * destruct l; inversion e; subst.
              rewrite DTP.gssLockRes in Lres.
              inversion Lres; subst.
              rewrite empty_map_spec.
              apply permDisjoint_comm.
              exists (perm_of_res (m_phi jm' @ (b0, ofs0))); reflexivity.
            * rewrite DTP.gsoLockRes in Lres; try assumption.
              assert (exists smthng, JTP.lockRes js l = Some smthng).
              { inversion MATCH. specialize (mtch_locks l).
                rewrite Lres in mtch_locks.
                destruct (JTP.lockRes js l); inversion mtch_locks.
                exists l0; reflexivity. }
              destruct H as [smthng H].
              inversion MATCH.
              destruct smthng.
              (*smthng = Some r*)
              rewrite <- (mtch_locksRes _ _ _ H Lres b0 ofs0).
              apply join_permDisjoint.
              apply resource_at_joins.
              eapply (juicy_mem_lemmas.components_join_joins ).
              apply Hadd_lock_res.
              inversion Hcompatible.
              eapply compatible_threadRes_lockRes_join; eassumption.
              eapply JSEM.compatible_lockRes_join; eassumption.
              (*smthng = None*)
              rewrite (mtch_locksEmpty _ _ H Lres).
              rewrite empty_map_spec. apply permDisjoint_comm.
              exists (perm_of_res (m_phi jm' @ (b0, ofs0))); reflexivity.
              
          + inversion dinv0; apply permDisjoint_comm;
            eapply lock_res_threads. eassumption.
          + inversion dinv0. apply permDisjoint_comm;
            eapply lock_res_threads. eassumption.
      }
      { apply updLock_inv.
        - assumption. (*Another lemma for invariant.*)
        - cut ( exists p, DSEM.ThreadPool.lockRes ds (b, Int.intval ofs) = Some p).
          {
            intros HH i0 cnt . destruct HH as [p HH].
          inversion dinv.
          unfold permMapsDisjoint in lock_set_threads.
          specialize (lock_set_threads i0 cnt b (Int.intval ofs)).
          destruct lock_set_threads as [pu lst].
          rewrite DSEM.ThreadPool.lockSet_spec in lst.
          rewrite HH in lst; simpl in lst.
          generalize lst.
          destruct ((DSEM.ThreadPool.getThreadR cnt) !! b (Int.intval ofs)) as [perm|] eqn:AA;
            rewrite AA;  [destruct perm; intros H; try solve[ inversion H] | ]; exists (Some Writable); reflexivity. }
          { inversion MATCH; subst. specialize (mtch_locks (b,Int.intval ofs)).
          rewrite His_unlocked in mtch_locks.
          destruct (DSEM.ThreadPool.lockRes ds (b, Int.intval ofs)) eqn: AA; try solve[inversion mtch_locks].
          exists l. reflexivity. }
        - intros. apply empty_disjoint'.
        - apply permMapsDisjoint_comm; apply empty_disjoint'.
        - rewrite empty_map_spec. exists (Some Writable); reflexivity.
        - intros. simpl. inversion dinv. apply lock_res_set in H.
          apply permMapsDisjoint_comm in H.
          specialize (H b (Int.intval ofs)).
          rewrite DSEM.ThreadPool.lockSet_spec in H.
          cut ( ssrbool.isSome
                  (DSEM.ThreadPool.lockRes ds' (b, Int.intval ofs)) = true ).
          { intros HH. rewrite HH in H. destruct H as [pu H].
            exists (pu); assumption. }
          { inversion MATCH; subst. specialize (mtch_locks (b, Int.intval ofs)).
            rewrite His_unlocked in mtch_locks. 
            rewrite DTP.gsoThreadLPool.
            rewrite <- mtch_locks; reflexivity. }
      }
   
      - unfold ds''.
        apply MTCH_updLockN.
        unfold ds'.
        apply MTCH_update; auto.
        intros.
        {
          (*Can turn this into a mini-lemma to show virtue is "correct" *)
          clear - MATCH Hi Hadd_lock_res Hcompatible Hcmpt His_unlocked.
          (* Showing virtue is correct *)
          unfold computeMap.
          unfold PMap.get; simpl.
          rewrite PTree.gcombine; auto.
          unfold virtue, inflated_delta; simpl.
          rewrite PTree.gmap.
          rewrite PTree.gmap1.
          unfold option_map at 2.
          destruct ((snd (Mem.mem_access m)) ! b0) eqn:valb0MEM; simpl.
          - (*Some 1*)
            destruct ((snd (DSEM.ThreadPool.getThreadR Htid')) ! b0) eqn:valb0D; simpl.
            + (*Some 2*)
              destruct (d_phi @ (b0, ofs0)) eqn:valb0ofs0; rewrite valb0ofs0; simpl; try solve[reflexivity].
                 destruct ((Share.EqDec_share t Share.bot)) eqn:isBot; simpl; try solve [reflexivity].
                   { subst. (*bottom share*)
                     simpl. inversion MATCH; subst.
                     unfold PMap.get in mtch_perm.
                     specialize (mtch_perm b0 ofs0 i Hi Htid'); rewrite valb0D in mtch_perm.
                     rewrite <- mtch_perm. f_equal.
                     clear - Hadd_lock_res valb0ofs0.
                     (*unfold sepalg.join, Join_rmap in Hadd_lock_res.*)
                     apply (resource_at_join _ _ _ (b0, ofs0)) in Hadd_lock_res.
                     rewrite valb0ofs0 in Hadd_lock_res.
                     inversion Hadd_lock_res; subst.
                     - inversion RJ. rewrite Share.lub_bot in H1. subst rsh1; reflexivity.
                     - inversion RJ. rewrite Share.lub_bot in H1. subst rsh1; reflexivity.
                   }

               +(* None 2*)
                 destruct (d_phi @ (b0, ofs0)) eqn:valb0ofs0; rewrite valb0ofs0; simpl; try solve[reflexivity].
                 destruct ((Share.EqDec_share t Share.bot)) eqn:isBot; simpl; try solve [reflexivity].
                  { subst. (*bottom share*)
                     simpl. inversion MATCH; subst.
                     unfold PMap.get in mtch_perm.
                     specialize (mtch_perm b0 ofs0 i Hi Htid'); rewrite valb0D in mtch_perm.
                     rewrite <- mtch_perm. f_equal.
                     clear - Hadd_lock_res valb0ofs0.
                     (*unfold sepalg.join, Join_rmap in Hadd_lock_res.*)
                     apply (resource_at_join _ _ _ (b0, ofs0)) in Hadd_lock_res.
                     rewrite valb0ofs0 in Hadd_lock_res.
                     inversion Hadd_lock_res; subst.
                     - inversion RJ. rewrite Share.lub_bot in H1. subst rsh1; reflexivity.
                     - inversion RJ. rewrite Share.lub_bot in H1. subst rsh1; reflexivity.
                  }
             - (*None 1*)
               destruct ((snd (DSEM.ThreadPool.getThreadR Htid')) ! b0) eqn:valb0D; simpl.
               inversion MATCH; subst.
               unfold PMap.get in mtch_perm.
               specialize (mtch_perm b0 ofs0 i Hi Htid'); rewrite valb0D in mtch_perm.
               pose (Hcompatible':= Hcompatible).
               apply JSEM.thread_mem_compatible in Hcompatible'.
               move Hcompatible at bottom. specialize (Hcompatible' i Hi).
               inversion Hcompatible'.
               specialize (acc_coh (b0, ofs0)).
               unfold max_access_at, PMap.get  in acc_coh; simpl in acc_coh.
               rewrite valb0MEM in acc_coh.
               simpl in acc_coh.
               rewrite mtch_perm in acc_coh.
               rewrite JSEM.Mem_canonical_useful in acc_coh. destruct (o ofs0); try solve[inversion acc_coh].
               + (*Some 1.1*)
                 (*TODO: This lemma should be moved, but don't know where yet. *)
                 Lemma blah: forall r, perm_of_res r = None ->
                                  r = NO Share.bot.
                 Proof.  intros. destruct r; try solve[reflexivity]; inversion H.
                         destruct (eq_dec t Share.bot); subst; try solve[reflexivity]; try solve[inversion H1].
                         destruct k; inversion H1.
                         apply perm_of_empty_inv in H1; destruct H1 as [A B] . subst t.
                         exfalso; eapply (juicy_mem_ops.Abs.pshare_sh_bot _ B).
                 Qed.
                 apply blah in mtch_perm.
                 apply (resource_at_join _ _ _ (b0, ofs0)) in Hadd_lock_res.
                 move Hadd_lock_res at bottom. rewrite mtch_perm in Hadd_lock_res.
                 apply join_unit1_e in Hadd_lock_res; try solve[ exact NO_identity].
                 rewrite <- Hadd_lock_res.
                 assert (Hcmpt':= Hcmpt).
                 apply JSEM.lock_mem_compatible in Hcmpt'.
                 apply Hcmpt' in His_unlocked.
                 inversion His_unlocked.
                 specialize (acc_coh0 (b0, ofs0)).
                 unfold max_access_at, PMap.get  in acc_coh0; simpl in acc_coh0.
                 rewrite valb0MEM in acc_coh0.
                 rewrite JSEM.Mem_canonical_useful in acc_coh0.
                 destruct (perm_of_res (d_phi @ (b0, ofs0))); try solve[inversion acc_coh0].
                 reflexivity.

               + (*None 1.2*)
                 
                 apply (MTCH_compat _ _ _ MATCH) in Hcompatible.
                 rewrite (@threads_canonical _ m _ Htid'); [|eapply MTCH_compat; eassumption].
                 replace (m_phi jm' @ (b0, ofs0)) with (NO Share.bot).
                 simpl.
                 rewrite if_true; reflexivity.
                 apply (resource_at_join _ _ _ (b0, ofs0)) in Hadd_lock_res.
                 replace (JSEM.ThreadPool.getThreadR Hi @ (b0, ofs0)) with (NO Share.bot) in Hadd_lock_res.
                 replace (d_phi @ (b0, ofs0)) with (NO Share.bot) in Hadd_lock_res.
                 - apply join_unit1_e in Hadd_lock_res.
                 assumption.
                 apply NO_identity.
                 - clear Hadd_lock_res.
                   symmetry.
                   
                   destruct
                     (compatible_lockRes_cohere _
                                                His_unlocked
                                                Hcmpt).
                   clear - acc_coh valb0MEM.
                   admit. (*This will change when I change acc_coh back.*)
                 - symmetry.
                   destruct
                     (compatible_threadRes_cohere Hi
                                                  Hcmpt).
                   clear - acc_coh valb0MEM.
                  admit. (*This will change when I change acc_coh back.*)
        }
           
           assert (H: exists l, DSEM.ThreadPool.lockRes ds (b, Int.intval ofs) = Some l).
           { inversion MATCH; subst.
             specialize (mtch_locks (b, (Int.intval ofs) )).
             rewrite His_unlocked in mtch_locks.
             destruct (DSEM.ThreadPool.lockRes ds (b, Int.intval ofs)); try solve[inversion mtch_locks]. exists l; reflexivity. }
           destruct H as [l dlockRes].
         - econstructor 1.
           + assumption.
           + eapply MTCH_getThreadC; eassumption.
           + eassumption.
           + eapply MTCH_compat; eassumption.
           + instantiate(1:=(restrPermMap
               (JSEM.mem_compatible_locks_ltwritable Hcompatible))). 
             apply restrPermMap_ext.
             intros b0.
             inversion MATCH; subst.
             extensionality ofs0.
             rewrite DSEM.ThreadPool.lockSet_spec.
             rewrite JSEM.ThreadPool.lockSet_spec.
             generalize (mtch_locks (b0, ofs0)).
             destruct (ssrbool.isSome (DSEM.ThreadPool.lockRes ds (b0, ofs0)));
             intros HH; rewrite HH; reflexivity.
           + assumption.
           + assumption.
           + exact dlockRes.
           + Focus 2. reflexivity.
           + Focus 2. unfold ds'', ds'.
             replace (MTCH_cnt MATCH Hi) with Htid'.
             reflexivity.
             apply proof_irrelevance.
           + (*constructor. 
             intros. left. *)
             admit. (*angelSpec!!! *)
    }  
    
    (* step_release *)
    {
      
    assert (Htid':= MTCH_cnt MATCH Hi).
    pose (inflated_delta:=
            fun loc => match (d_phi @ loc ) with
                      NO s => if Share.EqDec_share s Share.bot then None else Some ( perm_of_res ((m_phi jm') @ loc))
                    | _ => Some (perm_of_res ((m_phi jm') @ loc))
                    end).
         pose (virtue:= PTree.map
                                      (fun (block : positive) (_ : Z -> option permission) (ofs : Z) =>
                                         (inflated_delta (block, ofs))) (snd (getCurPerm m)) ).
         pose (ds':= DSEM.ThreadPool.updThread Htid' (Kresume c Vundef)
                  (computeMap
                     (DSEM.ThreadPool.getThreadR Htid') virtue)).
         pose (ds'':= DSEM.ThreadPool.updLockSet ds' (b, Int.intval ofs)
              (JSEM.juice2Perm d_phi m)).
         exists ds''.
         split; [|split].
    - unfold ds''.
      cut (DSEM.invariant ds').
      { intros dinv'.
        apply updLock_inv.
        - assumption. (*Another lemma for invariant.*)
        - cut ( exists p, DSEM.ThreadPool.lockRes ds' (b, Int.intval ofs) = Some p).
          {
            intros HH i0 cnt . destruct HH as [p HH].
          inversion dinv'.
          unfold permMapsDisjoint in lock_set_threads.
          specialize (lock_set_threads i0 cnt b (Int.intval ofs)).
          destruct lock_set_threads as [pu lst].
          rewrite DSEM.ThreadPool.lockSet_spec in lst.
          rewrite HH in lst; simpl in lst.
          generalize lst.
          destruct ((DSEM.ThreadPool.getThreadR cnt) !! b (Int.intval ofs)) as [perm|] eqn:AA;
            rewrite AA;  [destruct perm; intros H; try solve[ inversion H] | ]; exists (Some Writable); reflexivity. }
          { inversion MATCH; subst. specialize (mtch_locks (b,Int.intval ofs)).
          rewrite His_locked in mtch_locks.
          destruct (DSEM.ThreadPool.lockRes ds (b, Int.intval ofs)) eqn: AA; try solve[inversion mtch_locks].
          exists l; assumption. }
        - intros.
          apply permDisjoint_permMapsDisjoint; intros b0 ofs0.
          rewrite <- JSEM.juic2Perm_correct.
          + inversion MATCH.
            { destruct (NatTID.eq_tid_dec i i0).
              - subst i0. rewrite (DTP.gssThreadRes).
                apply permDisjoint_comm.
                apply Disjoint_computeMap.
              - apply (@permDisjoint_sub ((JSEM.ThreadPool.getThreadR Hi) @ (b0, ofs0))).
                apply (@join_join_sub' _ _ _ ((m_phi jm') @ (b0, ofs0)) ).
                * apply resource_at_join. apply join_comm; assumption.
                * rewrite mtch_perm. inversion dinv.
                  apply permMapsDisjoint_permDisjoint. 
                  unfold DSEM.race_free in  no_race.
                  unfold ds' in cnt. rewrite (DTP.gsoThreadRes).
                  apply no_race.
                  assumption.
                  assumption.
            }
          intros b0 ofs0.
          
          (*rewrite <- JSEM.juic2Perm_correct.
          cut (permDisjoint (perm_of_res (d_phi @ (b0, ofs0))) ((DSEM.ThreadPool.getThreadR cnt) !! b0 ofs0)). { intros HH; destruct HH as [k HH]; exists k; assumption. }
          inversion MATCH. *)
          admit.
        - admit. (*waiting for acc_cohere to change*)
        - simpl. apply (resource_at_join _ _ _ (b, (Int.intval ofs))) in
              Hrem_lock_res.
          rewrite HJcanwrite in Hrem_lock_res.
          simpl in Hrem_lock_res.
          cut ((JSEM.juice2Perm d_phi m) !! b (Int.intval ofs) = None \/
               (JSEM.juice2Perm d_phi m) !! b (Int.intval ofs) = Some Nonempty).
          + intros HH; destruct HH as [A | A]; rewrite A;
            exists (Some Writable); reflexivity.
          + unfold JSEM.juice2Perm, JSEM.mapmap, PMap.get; simpl.
            rewrite PTree.gmap.
            rewrite PTree.gmap1.
            destruct ((snd (Mem.mem_access m)) ! b).
            * { simpl.
                destruct (d_phi @ (b, Int.intval ofs)) eqn: HH; rewrite HH; simpl.
                - destruct (eq_dec t Share.bot); [left|right]; reflexivity.
                - right.
                  unfold sepalg.join, Join_resource in Hrem_lock_res.
                  inversion Hrem_lock_res; reflexivity.
                - right; reflexivity.
              }
            * left; reflexivity.
        - intros. simpl. inversion dinv'. apply lock_res_set in H.
          apply permMapsDisjoint_comm in H.
          specialize (H b (Int.intval ofs)).
          rewrite DSEM.ThreadPool.lockSet_spec in H.
          cut ( ssrbool.isSome
                  (DSEM.ThreadPool.lockRes ds' (b, Int.intval ofs)) = true ).
          { intros HH. rewrite HH in H. destruct H as [pu H].
            exists (pu); assumption. }
          { inversion MATCH; subst. specialize (mtch_locks (b, Int.intval ofs)).
            rewrite His_locked in mtch_locks. 
            rewrite DTP.gsoThreadLPool.
            rewrite <- mtch_locks; reflexivity. }
      }
      { (*Proof DSEM.invariant ds'*)
        apply updThread_inv.
        - assumption.
        - intros.
          apply Disjoint_computeMap.
          intros.
          unfold deltaMap_cases_analysis'; destruct (deltaMap_dec virtue b0 ofs0).
          + unfold virtue in e. rewrite PTree.gmap in e.
            destruct ((snd (getCurPerm m)) ! b0); inversion e.
            rewrite <- H1 in e0.
            unfold inflated_delta in e0.
            replace p with (perm_of_res (m_phi jm' @ (b0, ofs0))).
            { inversion MATCH. rewrite <- (mtch_perm b0 ofs0 j (mtch_cnt' j cnt) _).
              apply join_permDisjoint. apply resource_at_joins.
              eapply (join_sub_joins_trans ).
              apply join_comm in Hrem_lock_res.
              apply (join_join_sub Hrem_lock_res).
              eapply compatible_threadRes_join; eassumption. }
            { destruct (d_phi @ (b0, ofs0));
              [destruct (Share.EqDec_share t Share.bot) | |]; inversion e0;
              reflexivity. }
          +  inversion MATCH.
             rewrite <- (mtch_perm b0 ofs0 _ (mtch_cnt' _ Htid'));
               rewrite <- (mtch_perm b0 ofs0 _ (mtch_cnt' _ cnt)).
             apply join_permDisjoint;  apply resource_at_joins.
             eapply compatible_threadRes_join; eassumption.
          + inversion MATCH.
             rewrite <- (mtch_perm b0 ofs0 _ (mtch_cnt' _ Htid'));
               rewrite <- (mtch_perm b0 ofs0 _ (mtch_cnt' _ cnt)).
             apply join_permDisjoint;  apply resource_at_joins.
             eapply compatible_threadRes_join; eassumption.
        - intros. apply permMapsDisjoint_comm.

          apply Disjoint_computeMap.
          intros.

          cut (permDisjoint ((DSEM.ThreadPool.getThreadR Htid') !! b0 ofs0)
                            ((DSEM.ThreadPool.lockSet ds) !! b0 ofs0)).
          { intros CUT.
            unfold deltaMap_cases_analysis'; destruct (deltaMap_dec virtue b0 ofs0).
            + unfold virtue in e. rewrite PTree.gmap in e.
              destruct ((snd (getCurPerm m)) ! b0); inversion e.
              rewrite <- H0 in e0.
              unfold inflated_delta in e0.
              replace p with (perm_of_res (m_phi jm' @ (b0, ofs0))).
              {
                apply (permDisjoint_sub ((JSEM.ThreadPool.getThreadR Hi) @ (b0, ofs0)) ).
                apply resource_at_join_sub.
                apply join_comm in Hrem_lock_res; apply (join_join_sub Hrem_lock_res).
                inversion MATCH. rewrite mtch_perm; assumption.
              }
              { destruct (d_phi @ (b0, ofs0));
                [destruct (Share.EqDec_share t Share.bot) | |]; inversion e0;
                reflexivity. }
            + assumption.
            + assumption. }

        { apply permDisjoint_comm.
          apply permMapsDisjoint_permDisjoint.
          inversion dinv. apply lock_set_threads. }

        - intros.
          intros. apply permMapsDisjoint_comm.
          apply Disjoint_computeMap.
          intros.
          cut (permDisjoint ((DSEM.ThreadPool.getThreadR Htid') !! b0 ofs0)
                            (pmap0 !! b0 ofs0)).
          { intros CUT.
            unfold deltaMap_cases_analysis'; destruct (deltaMap_dec virtue b0 ofs0).
            + unfold virtue in e. rewrite PTree.gmap in e.
              destruct ((snd (getCurPerm m)) ! b0); inversion e.
              rewrite <- H1 in e0.
              unfold inflated_delta in e0.
              replace p with (perm_of_res (m_phi jm' @ (b0, ofs0))).
              { inversion MATCH.
                apply (permDisjoint_sub ((JSEM.ThreadPool.getThreadR Hi) @ (b0, ofs0))).
                apply resource_at_join_sub.
                apply join_comm in Hrem_lock_res; apply (join_join_sub Hrem_lock_res).
                rewrite mtch_perm.
                inversion dinv.
                apply CUT.
              }
              { destruct (d_phi @ (b0, ofs0));
                [destruct (Share.EqDec_share t Share.bot) | |]; inversion e0;
                reflexivity. }
            + assumption.
            + assumption. }
          { apply permMapsDisjoint_permDisjoint.
            apply permMapsDisjoint_comm.
            inversion dinv.
            eapply lock_res_threads; eassumption. }
                
          
      }
      
    - (*match_st*)
      unfold ds''.
      apply MTCH_updLockS.
      Focus 2.
      {
      inversion MATCH; subst.
      intros; apply JSEM.juic2Perm_correct.
      inversion Hcompatible; inversion H.
      eapply mem_cohere_sub.
      - eassumption.
      - eapply join_sub_trans.
        + unfold join_sub. exists (m_phi jm'). eassumption.
        + eapply compatible_threadRes_sub.
      assumption. }

      Unfocus.
      unfold ds'.
      apply MTCH_update; auto.
      intros.
      (*This is going tot ake some work. If its false the definitions can easily change. *)
      admit.

      assert (H: exists l, DSEM.ThreadPool.lockRes ds (b, Int.intval ofs) = Some l).
      { inversion MATCH; subst.
        specialize (mtch_locks (b, (Int.intval ofs) )).
        rewrite His_locked in mtch_locks.
        destruct (DSEM.ThreadPool.lockRes ds (b, Int.intval ofs)); try solve[inversion mtch_locks]. exists l; reflexivity. }
           destruct H as [l dlockRes].
    - econstructor 2.
      + assumption.
      + eapply MTCH_getThreadC; eassumption.
      + eassumption.
(*      + eapply MTCH_compat; eassumption. *)
      + instantiate(1:=(restrPermMap
               (JSEM.mem_compatible_locks_ltwritable Hcompatible))). 
             apply restrPermMap_ext.
             intros b0.
             inversion MATCH; subst.
             extensionality ofs0.
             rewrite DSEM.ThreadPool.lockSet_spec.
             rewrite JSEM.ThreadPool.lockSet_spec.
             generalize (mtch_locks (b0, ofs0)).
             destruct (ssrbool.isSome (DSEM.ThreadPool.lockRes ds (b0, ofs0)));
             intros HH; rewrite HH; reflexivity.
      + assumption.
      + assumption.
      + exact dlockRes.
      + Focus 2. reflexivity.
      + Focus 2. unfold ds'', ds'. 
        replace (MTCH_cnt MATCH Hi) with Htid'.
        reflexivity.
        apply proof_irrelevance.
      + admit. (*angelSpec!!!*)
    }

    (* step_create *)
    { 

      (* This step needs a complete overhaul!*)
      (* Will work on this once all other steps are 'reliably' proven. *)
      admit.
    }

    
    (* step_mklock *)
    { 
      assert (Htid':= MTCH_cnt MATCH Hi).
     (* (Htp': tp' = updThread cnt0 (Kresume c) pmap_tid')
            (Htp'': tp'' = updLockSet tp' pmap_lp), *)
      pose (pmap_tid  := DTP.getThreadR Htid').
      pose (pmap_tid' := setPermBlock (Some Nonempty) b (Int.intval ofs) pmap_tid LKSIZE_nat).
      pose (pmap_lp   := setPerm (Some Writable) b (Int.intval ofs)
                                               (DTP.lockSet ds)).

      pose (ds':= DTP.updThread Htid' (Kresume c Vundef) pmap_tid').
      pose (ds'':= DTP.updLockSet ds' (b, Int.intval ofs) empty_map).

      exists ds''.
      split ; [|split].
      - (*DSEM.invariant ds''*)
        cut (DSEM.invariant ds').
        { intros dinv'.
          apply updLock_inv.
        - assumption.
        - intros i0 cnt0.
          simpl (fst (b, Int.intval ofs)).
          simpl (snd (b, Int.intval ofs)).
          assert ((DTP.getThreadR cnt0) !! b (Int.intval ofs) = None \/
                 (DTP.getThreadR cnt0) !! b (Int.intval ofs) = Some Nonempty).
          {  destruct (NatTID.eq_tid_dec i i0).
             - right. subst i0. 
               rewrite DTP.gssThreadRes. unfold pmap_tid'.
               admit. (*Spec of setPermBlock: eassy lemma*)
             - rewrite DTP.gsoThreadRes.
               inversion MATCH. rewrite <- (mtch_perm _ _ _ (mtch_cnt' _ cnt0)).
               
               assert (HH:= compatible_threadRes_join Hcmpt Hi (mtch_cnt' i0 cnt0)).
               destruct HH as [SOME_RES HH]. assumption.
               apply (resource_at_join _ _ _ (b, Int.intval ofs)) in HH.
               rewrite Hpersonal_juice in HH.
               destruct (Hct (Int.intval ofs)) as [val Hlock_old].
               { replace (Int.intval ofs - Int.intval ofs) with 0.
                 unfold juicy_machine.LKSIZE, juicy_machine.LKCHUNK; simpl.
                 split; omega. 
                 apply Zminus_diag_reverse. }
               rewrite Hlock_old in HH.
               apply YES_join_full in HH.
               destruct HH as [? HH]. rewrite HH; simpl.
               destruct (eq_dec x Share.bot); auto.
               assumption.
          }
          { destruct H1 as [HH | HH]; rewrite HH; exists (Some Writable); reflexivity. }
        - intros. apply empty_disjoint'.
        - apply permMapsDisjoint_comm; apply empty_disjoint'.
        - rewrite empty_map_spec. exists (Some Writable); reflexivity.
        - intros; simpl.
          rewrite DTP.gsoThreadLPool in H1.
               cut (exists loprmap, JTP.lockRes js l = Some loprmap).
               { intros HH; destruct HH as [loprmap HH].
                 destruct loprmap.
                 - inversion MATCH.
                   rewrite <- (mtch_locksRes l r pmap0 HH H1 b (Int.intval ofs)).
                   assert (AA:= compatible_threadRes_lemmaRes_join _ _ _ _
                                                                   Hcompatible
                                                                   HH i Hi ).
                   destruct AA as [result AA].
                   apply (resource_at_join _ _ _ (b, Int.intval ofs))  in AA.
                   destruct (Hct (Int.intval ofs)) as [val Hlock_old].
                   { replace (Int.intval ofs - Int.intval ofs) with 0.
                     unfold juicy_machine.LKSIZE, juicy_machine.LKCHUNK; simpl.
                     split; omega. 
                     apply Zminus_diag_reverse. }
                   rewrite Hpersonal_juice in AA;
                     rewrite Hlock_old in AA.
                   apply YES_join_full in AA.
                   destruct AA as [some_share AA].
                   rewrite AA; simpl.
                   exists (Some Writable); destruct (eq_dec some_share Share.bot); reflexivity.
                 - inversion MATCH.
                   eapply mtch_locksEmpty in HH; try eassumption.
                   rewrite HH. rewrite empty_map_spec. exists (Some Writable); reflexivity.
               }
               inversion MATCH. specialize (mtch_locks l); rewrite H1 in mtch_locks.
               destruct (JSEM.ThreadPool.lockRes js l); try solve[inversion mtch_locks].
               exists l0; reflexivity.
        }
        { (*DSEM.invariant ds' *)
          apply updThread_inv.
          - eassumption.
          - intros.
            Lemma setPerm_spec_1:
              forall b ofs ofs0 perm size X,
                Intv.In ofs0 (ofs, ofs+size)->
                (setPermBlock X b ofs perm (Z.to_nat size)) !! b ofs0 = X.
                  intros. unfold setPermBlock.
                  pose (k:= (Z.to_nat size)).
                  assert (Z.to_nat size = k); try reflexivity.
                  fold k; induction k.
                  replace ofs0 with ofs.
                  - Lemma gssSetPerm: forall X b ofs perm,
                      (setPerm X b ofs perm) !! b ofs = X.
                    Proof. Admitted.
                    rewrite gssSetPerm; reflexivity.
                  - admit.
            Admitted.
             Lemma setPerm_spec_2:
               forall b ofs ofs0 perm size X,
                 ~ Intv.In ofs0 (ofs, ofs+size)->
                 (setPermBlock X b ofs perm (Z.to_nat size)) !! b ofs0 = perm !! b ofs0.
             Admitted.
             Lemma setPerm_spec_3:
               forall b b0 ofs ofs0 perm size X,
                 b <> b0 ->
                 (setPermBlock X b ofs perm (Z.to_nat size)) !! b0 ofs0 = perm !! b0 ofs0.
             Admitted.
            apply permDisjoint_permMapsDisjoint. intros b0 ofs0.
            unfold pmap_tid'.

            destruct (ident_eq b b0).
            + subst b0.
              destruct (Intv.In_dec ofs0 ((Int.intval ofs), (Int.intval ofs)+LKSIZE)).
              * { rewrite setPerm_spec_1; try assumption.
                  simpl.
                  inversion MATCH. erewrite <- mtch_perm.
                  Lemma permDisjointLT: forall a b c,
                      permDisjoint a c ->
                      Mem.perm_order'' a b ->
                      permDisjoint b c.
                        intros a b c H1 H2.
                        destruct a, b; try solve[inversion H2];
                        try solve[exists c; reflexivity].
                        simpl in H2.
                        destruct H1 as [k H1].
                        inversion H2; subst.
                        - exists k; assumption.
                        - destruct c; inversion H1.
                          exists (Some p0); reflexivity.
                        - destruct c; inversion H1.
                          destruct p; inversion H0.
                          exists (Some Readable); reflexivity.
                        - exists (Some Readable); reflexivity.
                        - destruct c; inversion H1;
                          try solve[exists (Some Nonempty); reflexivity].
                          destruct p; inversion H0; try(destruct p0; inversion H3);
                          try solve[exists (Some Nonempty); reflexivity];
                          try solve[exists (Some Readable); reflexivity];
                          try solve[exists (Some Writable); reflexivity].
                  Qed.
                  eapply (permDisjointLT (perm_of_res (JTP.getThreadR Hi @ (b, ofs0)))).
                  apply join_permDisjoint.
                  apply resource_at_joins.
                  eapply compatible_threadRes_join.
                  eassumption.
                  assumption.
                  rewrite Hpersonal_juice.
                  destruct (Hct ofs0) as [v Hct'].
                  admit. (*z arithmetic and intervals*)
                  rewrite Hct'; simpl.
                  unfold perm_of_sh, fullshare.
                  rewrite if_true.
                  destruct (eq_dec sh Share.top); simpl; constructor.
                  reflexivity.
                }
              * { rewrite setPerm_spec_2; try assumption.
                  inversion dinv.
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid. apply no_race; assumption. }
            + { rewrite setPerm_spec_3; try assumption.
                inversion dinv.
                apply permMapsDisjoint_permDisjoint.
                unfold pmap_tid. apply no_race; assumption. }
          - intros.
            apply permDisjoint_permMapsDisjoint. intros b0 ofs0.
            unfold pmap_tid'.

            destruct (ident_eq b b0).
            + subst b0.
              destruct (Intv.In_dec ofs0 ((Int.intval ofs), (Int.intval ofs)+LKSIZE)).
              * { rewrite setPerm_spec_1; try assumption.
                  simpl.
                  inversion MATCH.
                  rewrite DSEM.ThreadPool.lockSet_spec.
                  destruct (ssrbool.isSome (DSEM.ThreadPool.lockRes ds (b, ofs0))) eqn:EN;
                    rewrite EN.
                  - exists (Some Writable); reflexivity.
                  - exists (Some Nonempty); reflexivity.
                }
              * { rewrite setPerm_spec_2; try assumption.
                  inversion dinv.
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid. apply lock_set_threads; assumption. }
            + { rewrite setPerm_spec_3; try assumption.
                inversion dinv.
                apply permMapsDisjoint_permDisjoint.
                unfold pmap_tid. apply lock_set_threads; assumption. }

          - intros.
            apply permDisjoint_permMapsDisjoint. intros b0 ofs0.
            unfold pmap_tid'.
            
            destruct (ident_eq b b0).
            + subst b0.
              destruct (Intv.In_dec ofs0 ((Int.intval ofs), (Int.intval ofs)+LKSIZE)).
              * { rewrite setPerm_spec_1; try assumption.
                  simpl.
                  apply permDisjoint_comm.
                  apply (permDisjointLT (pmap_tid !! b ofs0)).
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid.
                  inversion dinv.
                  apply permMapsDisjoint_comm.
                  eapply lock_res_threads; eassumption.
                  unfold pmap_tid.
                  inversion MATCH.
                  erewrite <- (mtch_perm _ _ _ Hi).
                  rewrite Hpersonal_juice.
                  destruct (Hct ofs0) as [v Hct'].
                  admit.
                  rewrite Hct'. simpl.
                  unfold perm_of_sh, fullshare.
                  rewrite if_true.
                  destruct (eq_dec sh Share.top); simpl; constructor.
                  reflexivity. }
              * { rewrite setPerm_spec_2; try assumption.
                  inversion dinv.
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid. eapply lock_res_threads; eassumption. }
            + { rewrite setPerm_spec_3; try assumption.
                inversion dinv.
                apply permMapsDisjoint_permDisjoint.
                unfold pmap_tid. eapply lock_res_threads; eassumption. }
        }
        
      - rewrite Htp''; unfold ds''.
        apply MTCH_updLockN.
        rewrite Htp'; unfold ds'.
        apply MTCH_update.
        assumption.

        (* Now I prove the map construction is correct*)
        {
          inversion MATCH; subst js0 ds0.
          unfold pmap_tid', pmap_tid.
          intros.
          (*unfold setPerm.*)
          destruct (ident_eq b0 b). rewrite e.
          + (*I consider three cases:
             * ofs = ofs0 
             * 0 < ofs0 - ofs < LOCKSIZE 
             * ~ 0 < ofs0 - ofs <= LOCKSIZE
             *)
            admit. (*This should come from the specification of setPermBlock. *)
            (* destruct (Intv.In_dec (ofs0 - (Int.intval ofs))%Z (0, LKSIZE));
              [ destruct (zeq (Int.intval ofs) ofs0)| ].
            * (* ofs = ofs0 *)
              rewrite e0 in Hlock. 
              rewrite Hlock; reflexivity.
            * (* n0 < ofs0 - ofs < LOCKSIZE *)
              move Hct at bottom. 
              rewrite Hct.
              simpl.
              { 
                destruct i0 as [lineq rineq]; simpl in lineq, rineq.
                split; try assumption.
                apply Z.le_neq; split; [assumption  |].
                unfold not; intros HH; apply n; symmetry.
                apply Zminus_eq; symmetry.
                exact HH. }
            
          * erewrite <- Hj_forward. *)
          + admit. (*again this comes from the specification of setPermBlock with b<>b0*)
        }
        
      - econstructor 4. (*The step *)
        + assumption.
        + eapply MTCH_getThreadC; eassumption.
        + eassumption.
        (*      + eapply MTCH_compat; eassumption. *)
        + instantiate(1:= m_dry jm).
          subst tp''.
          rewrite <- Hpersonal_perm.
          erewrite <- (MTCH_restrict_personal ).
          reflexivity.
          assumption.
        + rewrite <- Hright_juice; assumption.
        + reflexivity.
        + reflexivity.
        + replace (MTCH_cnt MATCH Hi) with Htid'.
          reflexivity.
          apply proof_irrelevance.
    }
    admit.
    (*
    (* step_freelock *)
    { assert (Htid':= MTCH_cnt MATCH Hi).
     (* (Htp': tp' = updThread cnt0 (Kresume c) pmap_tid')
            (Htp'': tp'' = updLockSet tp' pmap_lp), *)
      Definition WorF (sh: share): permission:=
        if eq_dec sh Share.top then Freeable else Writable.
      pose (pmap_tid  := DTP.getThreadR Htid').
      pose (pmap_tid' := (computeMap pmap_tid virtue)).
      pose (ds':= DSEM.ThreadPool.updThread Htid' (Kresume c Vundef)
                                            (computeMap
                                               (DSEM.ThreadPool.getThreadR Htid') virtue)) ).
      pose (pmap_tid' := setPermBlock (Some (WorF sh)) b (Int.intval ofs) pmap_tid LKSIZE_nat).
(*      pose (pmap_tid' := (setPermBlock (Some (WorF sh)) b (Int.intval ofs)
           (DSEM.ThreadPool.getThreadR Htid') LKSIZE_nat)))*)
      
      
      pose (ds':= DTP.updThread Htid' (Kresume c Vundef) pmap_tid').
      pose (ds'':= DTP.remLockSet ds' (b,(Int.intval ofs))).

      exists ds''.
      split ; [|split].

      unfold ds''; rewrite DSEM.ThreadPool.remLock_updThread_comm.
      pose (ds0:= (DSEM.ThreadPool.remLockSet ds (b, (Int.intval ofs)))).
      
      - cut (DSEM.invariant ds0).
        { (*DSEM.invariant ds' *)
          intros dinv0.
          apply updThread_inv.
          - eassumption.
          - intros.
            apply permDisjoint_permMapsDisjoint. intros b0 ofs0.
            unfold pmap_tid'.
            
            destruct (ident_eq b b0).
            + subst b0.
              destruct (Intv.In_dec ofs0 ((Int.intval ofs), (Int.intval ofs)+LKSIZE)).
              * { rewrite setPerm_spec_1; try assumption.
                  inversion MATCH.
                  rewrite DSEM.ThreadPool.gRemLockSetRes.
                  erewrite <- (mtch_perm _ _ _ (mtch_cnt' _ cnt) ).
                  
                  Definition WorF_backwards sh:=
                    if proj_sumbool (eq_dec sh Share.top) then  None else Some Nonempty.
                  apply permDisjoint_comm.
                  apply (permDisjointLT (WorF_backwards sh)).
                  unfold WorF, WorF_backwards.
                  destruct (eq_dec sh Share.top) eqn:EN; rewrite EN; simpl.
                  - exists (Some Freeable); reflexivity.
                  - exists (Some Writable); reflexivity.
                    cut (joins (JTP.getThreadR Hi )
                             (JTP.getThreadR (mtch_cnt' j cnt))).
                    { intros JOINS.
                      (*HERE stuck*)
                    assert (HH:= resource_at_joins _ _ JOINS (b, ofs0)).
                    destruct (zeq ofs0 (Int.intval ofs)).
                    - subst ofs0.
                      rewrite Hlock in HH.
                      inversion HH. inversion H3; subst.
                      +
                        simpl.
                        unfold WorF_backwards.
                        destruct (eq_dec sh Share.top); try subst sh.
                        inversion RJ.
                        rewrite Share.glb_commute in H0.
                        rewrite Share.glb_top in H0; inversion H0.
                        rewrite if_true; auto.
                        simpl; trivial.
                        simpl.
                        destruct (eq_dec rsh2 Share.bot ); constructor.
                      + simpl.
                        unfold WorF_backwards.
                        destruct (eq_dec sh Share.top); try subst sh.
                        inversion H10. simpl in H0.
                        rewrite Share.glb_commute in H0.
                        rewrite Share.glb_top in H0. unfold lifted_obj in H0.
                        apply juicy_mem_ops.Abs.pshare_sh_bot in H0.
                        exfalso; assumption.
                      + constructor.
                    - simpl.
                      assert ( exists X sh,
                          JSEM.ThreadPool.getThreadR Hi @ (b, ofs0) =
                          YES sh pfullshare (CT (ofs0 - Int.intval ofs))
                              X).
                      { assert (AA:=
                                  phi_valid (JSEM.ThreadPool.getThreadR Hi) b (Int.intval ofs)).
                        unfold compose in AA.
                        rewrite Hlock in AA; simpl in AA.
                        assert (BB: 0 < ofs0 - (Int.intval ofs) < LKSIZE ).
                        { inversion i0. simpl in H4, H3; omega. }
                        apply AA in BB.
                        replace (Int.intval ofs + (ofs0 - Int.intval ofs)) with ofs0 in BB
                          by xomega.
                        destruct (JSEM.ThreadPool.getThreadR Hi @ (b, ofs0)); inversion BB.
                        exists p0, t; reflexivity. }
                      destruct H3 as [X [sh2 BB]].
                        
                        
                        inversion RJ.
                        rewrite Share.glb_commute in H0.
                        rewrite Share.glb_top in H0; inversion H0.
                        simpl (proj_sumbool (left eq_refl)).
                        rewrite if_true.
                        rewrite if_true; auto.
                        simpl; trivial.
                        simpl.
                        destruct (eq_dec rsh2 Share.bot ); constructor.
                      auto.
                      
                  eapply (permDisjointLT (perm_of_res (JTP.getThreadR Hi @ (b, ofs0)))).
                  apply join_permDisjoint.
                  apply resource_at_joins.
                  eapply compatible_threadRes_join.
                  eassumption.
                  assumption.
                  rewrite Hpersonal_juice.
                  destruct (Hct ofs0) as [v Hct'].
                  admit. (*z arithmetic and intervals*)
                  rewrite Hct'; simpl.
                  unfold perm_of_sh, fullshare.
                  rewrite if_true.
                  destruct (eq_dec sh Share.top); simpl; constructor.
                  reflexivity.
                }
              * { rewrite setPerm_spec_2; try assumption.
                  inversion dinv.
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid. apply no_race; assumption. }
            + { rewrite setPerm_spec_3; try assumption.
                inversion dinv.
                apply permMapsDisjoint_permDisjoint.
                unfold pmap_tid. apply no_race; assumption. }
          - intros.
            apply permDisjoint_permMapsDisjoint. intros b0 ofs0.
            unfold pmap_tid'.

            destruct (ident_eq b b0).
            + subst b0.
              destruct (Intv.In_dec ofs0 ((Int.intval ofs), (Int.intval ofs)+LKSIZE)).
              * { rewrite setPerm_spec_1; try assumption.
                  simpl.
                  inversion MATCH.
                  rewrite DSEM.ThreadPool.lockSet_spec.
                  destruct (ssrbool.isSome (DSEM.ThreadPool.lockRes ds (b, ofs0))) eqn:EN;
                    rewrite EN.
                  - exists (Some Writable); reflexivity.
                  - exists (Some Nonempty); reflexivity.
                }
              * { rewrite setPerm_spec_2; try assumption.
                  inversion dinv.
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid. apply lock_set_threads; assumption. }
            + { rewrite setPerm_spec_3; try assumption.
                inversion dinv.
                apply permMapsDisjoint_permDisjoint.
                unfold pmap_tid. apply lock_set_threads; assumption. }

          - intros.
            apply permDisjoint_permMapsDisjoint. intros b0 ofs0.
            unfold pmap_tid'.
            
            destruct (ident_eq b b0).
            + subst b0.
              destruct (Intv.In_dec ofs0 ((Int.intval ofs), (Int.intval ofs)+LKSIZE)).
              * { rewrite setPerm_spec_1; try assumption.
                  simpl.
                  apply permDisjoint_comm.
                  apply (permDisjointLT (pmap_tid !! b ofs0)).
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid.
                  inversion dinv.
                  apply permMapsDisjoint_comm.
                  eapply lock_res_threads; eassumption.
                  unfold pmap_tid.
                  inversion MATCH.
                  erewrite <- (mtch_perm _ _ _ Hi).
                  rewrite Hpersonal_juice.
                  destruct (Hct ofs0) as [v Hct'].
                  admit.
                  rewrite Hct'. simpl.
                  unfold perm_of_sh, fullshare.
                  rewrite if_true.
                  destruct (eq_dec sh Share.top); simpl; constructor.
                  reflexivity. }
              * { rewrite setPerm_spec_2; try assumption.
                  inversion dinv.
                  apply permMapsDisjoint_permDisjoint.
                  unfold pmap_tid. eapply lock_res_threads; eassumption. }
            + { rewrite setPerm_spec_3; try assumption.
                inversion dinv.
                apply permMapsDisjoint_permDisjoint.
                unfold pmap_tid. eapply lock_res_threads; eassumption. }
        }









            (** * HERE  *)

            admit.  (*virtue is disjoint from other threads. *)
          - intros. admit. (*virtue is disjoint from lockSet. *)
          - intros. admit. (*virtue disjoint from other lock resources.*)
        }
        { 
          eapply remLock_inv.
          - assumption.
          - intros; simpl.
            cut (((DTP.getThreadR cnt) !! b (Int.intval ofs)) = Some Nonempty \/
                 ((DTP.getThreadR cnt) !! b (Int.intval ofs)) = None).
            { intros H; destruct H as [H | H]; rewrite H;
              exists (Some Writable); reflexivity. }
            { inversion MATCH; subst.
              destruct (NatTID.eq_tid_dec i i0).
              - subst i0.
                specialize (mtch_perm b (Int.intval ofs) i Hi cnt).
                 rewrite <- mtch_perm.
                 rewrite Hlock. left; reflexivity.
              - specialize (mtch_perm b (Int.intval ofs) i0 (mtch_cnt' _ cnt) cnt).
                rewrite <- mtch_perm.
                destruct (compatible_threadRes_join Hcompatible Hi (mtch_cnt' i0 cnt)) as
                [result HH].
                assumption.
                apply (resource_at_join _ _ _ (b, Int.intval ofs)) in HH.
                rewrite Hlock in HH.
                apply YES_join_full in HH. destruct HH as [rsh2 HH].
                rewrite HH; simpl.
                destruct (eq_dec rsh2 Share.bot); [right | left]; reflexivity.
            }
        }
        
      - unfold ds''.
        apply MTCH_remLockN.
        unfold ds'.
        apply MTCH_update.
        assumption.

        (* Now I prove the map construction is correct*)
        {
          admit.
        }
        
      - econstructor 5. (*The step *)
        
        + assumption.
        + eapply MTCH_getThreadC; eassumption.
        + eassumption.
        (*      + eapply MTCH_compat; eassumption. *)
        + instantiate(2:= Some (WorF sh) ). reflexivity.
        + reflexivity.
        + unfold ds'',  ds'.
        + replace (MTCH_cnt MATCH Hi) with Htid'.
          reflexivity. 
          apply proof_irrelevance.
          assumption.
    }
*) 
    (* step_acqfail *)
    {
      exists ds.
      split ; [|split].
      + assumption.
      + assumption.
      + { econstructor 6.
          + assumption.
          + inversion MATCH; subst.
            rewrite <- (mtch_gtc i Hi).
            eassumption.
          + eassumption.
          + reflexivity.
          + erewrite restrPermMap_ext.
            eassumption.
            intros b0.
            inversion MATCH; subst.
            admit. (*This should follow from mtch_locks. Just like in release*)
        }
    }
  Admitted.

    

  
  Lemma core_diagram':
    forall (m : mem)  (U0 U U': schedule) 
     (ds : dstate) (js js': jstate) 
     (m' : mem),
   match_st js ds ->
   DSEM.invariant ds ->
   corestep (JMachineSem U0) genv (U, js) m (U', js') m' ->
   exists (ds' : dstate),
     DSEM.invariant ds' /\
     match_st js' ds' /\
     corestep (DMachineSem U0) genv (U, ds) m (U', ds') m'.
       intros m U0 U U' ds js js' m' MATCH dinv.
       unfold JuicyMachine.MachineSemantics; simpl.
       unfold JuicyMachine.MachStep; simpl.
       intros STEP;
         inversion STEP; subst.
      
       (* start_step *)
       admit.
       
       (* resume_step *)
       inversion MATCH; subst.
       inversion Htstep; subst.
       exists (DTP.updThreadC (mtch_cnt _ ctn) (Krun c')).
       split;[|split].
       (*Invariant*)
       { apply updCinvariant; assumption. }
       (*Match *)
       { (*This should be a lemma *)
         apply MTCH_updt; assumption.
       }
       
       (*Step*)
       { econstructor 2; try eassumption.
         - simpl. eapply MTCH_compat; eassumption.
         - simpl. econstructor; try eassumption.
           + rewrite <- Hcode. symmetry. apply mtch_gtc.
           + reflexivity.
       }

       
       (* core_step *)
       {
         inversion MATCH; subst.
         inversion Htstep; subst.
         assert (Htid':=mtch_cnt _ Htid).
         exists (DTP.updThread Htid' (Krun c') (permissions.getCurPerm (m_dry jm'))).
         split ; [|split].
         { generalize dinv.
           (*Nick has this proof somewhere. *)
           admit.
         }
         { apply MTCH_update.
           assumption.
           intros.
           assert (HH:= juicy_mem_access jm').
           rewrite <- HH.
           rewrite getCurPerm_correct.
           reflexivity.
         }
         {  assert (Hcmpt': DSEM.mem_compatible ds m) by
               (eapply MTCH_compat; eassumption).

           econstructor; simpl.
           - eassumption.
           - econstructor; try eassumption.
             Focus 4. reflexivity.
             Focus 2. eapply (MTCH_getThreadC _ _ _ _ _ _ _ Hthread).
             Focus 2.
             simpl.
             inversion Hcorestep. apply H.
             instantiate(1:=Hcmpt').
             apply MTCH_restrict_personal.
             assumption.
         }
       }
           
       (* suspend_step *)
       inversion MATCH; subst.
       inversion Htstep; subst.
       exists (DTP.updThreadC (mtch_cnt _ ctn) (Kblocked c)).
       split;[|split].
       (*Invariant*)
       { apply updCinvariant; assumption. }
       (*Match *)
       { apply MTCH_updt; assumption.        }
       (*Step*)
       { econstructor 4; try eassumption.
         - simpl. reflexivity.
         - eapply MTCH_compat; eassumption.
         - simpl. econstructor; try eassumption.
           + rewrite <- Hcode. symmetry. apply mtch_gtc.
           + reflexivity.
       }

       (*Conc step*)
       {
         destruct (conc_step_diagram m m' U js js' ds tid genv MATCH dinv Htid Hcmpt HschedN Htstep)
           as [ds' [dinv' [MTCH' step']]]; eauto.
         exists ds'; split; [| split]; try assumption.
         econstructor 5; simpl; try eassumption.
         reflexivity.
       }
       
       (* step_halted *)
       exists ds.
       split; [|split]. 
       { assumption. }
       { assumption. }
       { inversion MATCH; subst. 
         assert (Htid':=Htid); apply mtch_cnt in Htid'.
         econstructor 6; try eassumption.
         simpl; reflexivity.
         simpl. eapply MTCH_compat; eassumption; instantiate(1:=Htid').
         eapply MTCH_halted; eassumption.
       }
       
           
       (* schedfail *)
       { exists ds.
       split;[|split]; try eassumption.
       econstructor 7; try eassumption; try reflexivity.
       unfold not; simpl; intros.
       apply Htid. inversion MATCH; apply mtch_cnt'; assumption. }
       
       Grab Existential Variables.
       - simpl. apply mtch_cnt. assumption.
       - assumption.
  Admitted.

  Lemma core_diagram:
    forall (m : mem)  (U0 U U': schedule) 
     (ds : dstate) (js js': jstate) 
     (m' : mem),
   corestep (JMachineSem U0) genv (U, js) m (U', js') m' ->
   match_st js ds ->
   DSEM.invariant ds ->
   exists (ds' : dstate),
     DSEM.invariant ds' /\
     match_st js' ds' /\
     corestep (DMachineSem U0) genv (U, ds) m (U', ds') m'.
  Proof.
    intros. destruct (core_diagram' m U0 U U' ds js js' m' H0 H1 H) as [ds' [A[B C]]].
    exists ds'; split;[|split]; try assumption.
  Qed.

  
  Lemma halted_diagram:
    forall U ds js,
      fst js = fst ds ->
      halted (JMachineSem U) js = halted (DMachineSem U) ds.
        intros until js. destruct ds, js; simpl; intros HH; rewrite HH.
        reflexivity.
  Qed.

End ClightParching.
Export ClightParching.

Module ClightErasure:= ErasureFnctr ClightParching.


(** BEHOLD THE THEOREM :) *)
(*Just to be explicit*)


Theorem clight_erasure:
  forall U : DryMachine.Sch,
       Wholeprog_sim.Wholeprog_sim (JMachineSem U) 
         (DMachineSem U) ClightParching.genv ClightParching.genv ClightParching.main ClightErasure.ge_inv
         ClightErasure.init_inv ClightErasure.halt_inv.
Proof.
  Proof. apply ClightErasure.erasure. Qed.