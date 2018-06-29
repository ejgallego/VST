
From mathcomp.ssreflect Require Import ssreflect ssrbool ssrnat ssrfun eqtype.

Require Import compcert.common.Globalenvs.

Require Import VST.concurrency.common.HybridMachineSig.
Import HybridMachineSig.
Set Bullet Behavior "Strict Subproofs".
  
Require Import VST.concurrency.compiler.concurrent_compiler_simulation.
Require Import VST.concurrency.compiler.concurrent_compiler_simulation_proof.
Require Import VST.concurrency.compiler.sequential_compiler_correct.
Require Import VST.concurrency.compiler.concurrent_compiler_safety.
Require Import VST.concurrency.compiler.concurrent_compiler_simulation_proof.
Require Import VST.concurrency.compiler.safety_equivalence.
Require Import VST.concurrency.compiler.HybridMachine_simulation.
Require Import VST.concurrency.common.HybridMachine.
Require Import Omega.
            

(*Clight Machine *)
Require Import VST.concurrency.common.ClightMachine.
(*Asm Machine*)
Require Import VST.concurrency.common.x86_context.

Module Concurrent_Safety (CC_correct: CompCert_correctness).
  (*Import the Clight Hybrid Machine*)
  Import ClightMachine.
  Import DMS.
  (*Import the Asm X86 Hybrid Machine*)
  Import X86Context.

  Module ConcurCC_correct:= (Concurrent_correctness CC_correct).
  Import ConcurCC_correct.
  
  Definition Clight_init_state (p: Clight.program):=
    Clight.entry_point (Clight.globalenv p).
  
  Definition Asm_init_state (p: Asm.program):=
    Asm.entry_point (@the_ge p).
  
  Notation valid Sem:=
    (valid dryResources Sem OrdinalPool.OrdinalThreadPool DryHybridMachineSig).

  Definition opt_init_mem_source (p : Clight.program):=
      (Genv.init_mem (Ctypes.program_of_program p)).
  Definition opt_init_mem_target {F V} (tp:AST.program F V ):=
    (Genv.init_mem tp).
  Lemma explicit_safety_step:
    forall (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemantincsForMachines.ClightSem (Clight.globalenv p)) in
         let SemTarget:= @X86Sem tp asm_genv_safety in
         forall (U : schedule) (m_s m_t : Memory.Mem.mem)
             (j : Values.Val.meminj) (c : Asm.state)
             (C_source : OrdinalPool.t(Sem:=SemSource))
             (C_target : OrdinalPool.t(Sem:=SemTarget)) tr
             (SIM : HybridMachine_simulation (ClightConcurSem (opt_init_mem_source p))
                                             (AsmConcurSem (opt_init_mem_target tp))) (cd : index SIM),
           match_state SIM cd j C_source m_s C_target
                    m_t ->
        (forall U,
          (valid SemSource) (tr, C_source, m_s) U ->
            explicit_safety
              HybridMachine.DryHybridMachine.dryResources
              SemSource
              (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
              HybridMachine.DryHybridMachine.DryHybridMachineSig
              U tr C_source m_s) ->
        forall U,
          (valid SemTarget) (tr, C_target, Asm.get_mem c) U ->
            explicit_safety
              HybridMachine.DryHybridMachine.dryResources
              SemTarget
              (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
              HybridMachine.DryHybridMachine.DryHybridMachineSig
              U tr C_target m_t.
    Proof.
    Admitted.

    Lemma match_valid_equiv:
      forall U (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemantincsForMachines.ClightSem (Clight.globalenv p)) in
        let SemTarget:= @X86Sem tp asm_genv_safety in
        forall (m_s m_t : Memory.Mem.mem)
          (j : Values.Val.meminj)
          (C_source : OrdinalPool.t(Sem:=SemSource))
          (C_target : OrdinalPool.t(Sem:=SemTarget)) tr
          (SIM : HybridMachine_simulation (ClightConcurSem (opt_init_mem_source p))
                                          (AsmConcurSem (opt_init_mem_target tp))) (cd : index SIM)
          (Hmatch: match_state SIM cd j C_source m_s C_target m_t),
          (valid SemSource) (tr, C_source, m_s) U <-> (valid SemTarget) (tr, C_target, m_t) U.
    Proof.
      intros.
      unfold valid. simpl.
      unfold correct_schedule.
      destruct (schedPeek U); [|now auto].
      now eapply (thread_running _ _ j _ _ _ _ Hmatch). 
    Qed.

    (* This lemma does not hold? *)
    Lemma explicit_safety_thread_stepN:
      forall (tp : Asm.program) tr
        (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemTarget:= @X86Sem tp asm_genv_safety in
        forall  n U (c c':  OrdinalPool.t(Sem:=SemTarget)) m m'
           (Hval: (valid SemTarget) (tr, c, m) U)
           (HstepN: machine_semantics_lemmas.thread_stepN
                      (AsmConcurSem (opt_init_mem_target tp)) (@the_ge tp) n U c m c' m')
           (Hsafe: explicit_safety
                     HybridMachine.DryHybridMachine.dryResources SemTarget
                     (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
                     HybridMachine.DryHybridMachine.DryHybridMachineSig
                     U tr c' m'),
          explicit_safety HybridMachine.DryHybridMachine.dryResources SemTarget
                          (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
                          HybridMachine.DryHybridMachine.DryHybridMachineSig
                          U tr c m.
    Proof.
      intros tp tr asm_genv_safety SemTarget n.
      induction n; intros.
      - simpl in HstepN.
        inversion HstepN; subst.
        now eauto.
      - simpl in HstepN.
        destruct HstepN as [c'' [m'' [Hstep HstepN]]].
        econstructor 2 with (y' := (tr, c'', m'')).
        simpl. eauto.
        intros.
        simpl in H.
        unfold valid, correct_schedule in H, Hval.
        simpl in H, Hval.
        destruct (schedPeek x') eqn:Hx.
        + simpl in H.
          unfold unique_Krun in H.
          inversion Hstep; subst.
          inversion Htstep; subst.
          assert (cnti:  ThreadPool.containsThread
                           (ThreadPool.updThread Htid (Krun c'0)
                                                 (permissions.getCurPerm m'0,
                                                  (ThreadPool.getThreadR Htid)#2)) tid)
            by (eapply ThreadPool.cntUpdate;
                eauto).
          assert (Hhalted: ~ @threadHalted SemTarget _ _ _ cnti).
          admit. (*False *)
          admit.
        + econstructor 1.
          simpl.
          unfold halted_machine.
          rewrite Hx.
          now auto.
    Admitted.
    
    Lemma explicit_safety_step':
      forall (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemantincsForMachines.ClightSem (Clight.globalenv p)) in
        let SemTarget:= @X86Sem tp asm_genv_safety in
        forall (m_s m_t : Memory.Mem.mem)
          (j : Values.Val.meminj)
          (C_source : OrdinalPool.t(Sem:=SemSource))
          (C_target : OrdinalPool.t(Sem:=SemTarget)) tr
          (SIM : HybridMachine_simulation (ClightConcurSem (opt_init_mem_source p))
                                          (AsmConcurSem (opt_init_mem_target tp))) (cd : index SIM),
          match_state SIM cd j C_source m_s C_target m_t ->
          (forall U,
              (valid SemSource) (tr, C_source, m_s) U ->
              explicit_safety
                HybridMachine.DryHybridMachine.dryResources
                SemSource
                (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
                HybridMachine.DryHybridMachine.DryHybridMachineSig
                U tr C_source m_s) ->
          forall U,
            (valid SemTarget) (tr, C_target, m_t) U ->
            explicit_safety
              HybridMachine.DryHybridMachine.dryResources
              SemTarget
              (threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
              HybridMachine.DryHybridMachine.DryHybridMachineSig
              U tr C_target m_t.
    Proof.
      intros p tp asm_genv_safety SemSource SemTarget.
      cofix HsafeT.
      intros m_s m_t j C_source C_target tr SIM cd Hmatch HsafeS U HvalidT.
      assert (HvalidS: (valid SemSource) (tr, C_source, m_s) U)
        by (eapply match_valid_equiv; eauto).
      specialize (HsafeS U HvalidS).
      inversion HsafeS as [HhaltedS | stS' Hstep CIH |].
      - (* halted case *)
        econstructor.
        simpl in *.
        remember (machine_semantics.conc_halted (ClightConcurSem (opt_init_mem_source p)) U
                                                C_source) as v1 eqn:Hhalted.
        symmetry in Hhalted.
        unfold halted_machine in *.
        simpl in *.
        destruct (schedPeek U);
          now auto.
      - (* internal step case *)
        destruct stS' as [[evS C_source'] m_s'].
        simpl in Hstep.
        pose proof Hstep as HstepS.
        eapply (thread_diagram SIM) with (sge := Clight.globalenv p) (tge := the_ge) in Hstep;
          eauto.
        destruct Hstep as [C_target' [m_t' [cd' [j' [Hmatch' HstepT]]]]].
        destruct HstepT as [HstepT | [HstepT Hdec]].
        + (* case the target machine takes one or more steps *)
          destruct HstepT as [n HstepT].
          simpl in HstepT.
          destruct HstepT as [C_target'' [m_t'' [HstepT HstepNT]]].
          (*Note: I guess the trace of the target machine here is not
          important because we do not maintain the trace for internal
          steps.*)
          eapply coinductive_safety.internal_safety with (y' := (evS, C_target'', m_t''));
            [now auto|].
          simpl.
          intros U' HvalidT'.
          assert (HvalidT'': (valid SemTarget) (evS, C_target', m_t') U)
            by admit.
          specialize (HsafeT m_s' m_t' j' _ _ _ SIM cd' Hmatch' CIH _ HvalidT'').
          eapply explicit_safety_thread_stepN with (U := U') (c' := C_target') (m' := m_t').
          admit.
          intros.
          Admitted.
          (*eapply explicit_safety_schedule_irr.
          unfold valid, correct_schedule in HvalidT'.
          simpl in HvalidT'.
          destruct (schedPeek U') eqn:HU'.
          * assert (Heq: schedPeek U = schedPeek U')
              by admit. (* by HvalidT, HvalidT' and internal steps *)
            assert (HvalidT'': (valid SemTarget) (evS, C_target', m_t') U)
              by admit.
            specialize (HsafeT m_s' m_t' j' _ _ _ SIM cd' Hmatch' CIH _ HvalidT'').
            simpl in HsafeT.
            pose proof (explicit_safety_schedule_irr _ _ _ _ _ _ _ _ _ Heq HsafeT).
            eapply explicit_safety_thread_stepN with (U := U');
            eauto.
          simpl in HsafeT.
          intros.
          eapply HsafeT; eauto.
          eapply CIH.
          eapply MachStep_preserve_valid in HstepS.
          assert (HvalidS': (valid SemSource) (evS, C_source''
          eapply match_valid_equiv in HvalidT'. *)
          

          
        
    Lemma Clight_finite_branching:
      let ClightSem:= ClightSemantincsForMachines.ClightSem in 
            forall (p : Clight.program)
                   (x : kstate dryResources (ClightSem (Clight.globalenv p)) OrdinalPool.OrdinalThreadPool),
              safety.finite_on_x
                (safety.possible_image
                   (fun
                       (x0 : kstate dryResources (ClightSem (Clight.globalenv p))
                                    OrdinalPool.OrdinalThreadPool) (y : schedule)
                       (x' : kstate dryResources (ClightSem (Clight.globalenv p))
                                    OrdinalPool.OrdinalThreadPool) =>
                       exists y' : schedule,
                         kstep dryResources (ClightSem (Clight.globalenv p)) OrdinalPool.OrdinalThreadPool
                               DryHybridMachineSig x0 y x' y') (valid (ClightSem (Clight.globalenv p))) x).
          Proof.
          Admitted.
    Lemma csafety_step:
      forall (p : Clight.program) (tp : Asm.program) (asm_genv_safety : Asm_core.safe_genv the_ge),
        let SemSource:= (ClightSemantincsForMachines.ClightSem (Clight.globalenv p)) in
         let SemTarget:= @X86Sem tp asm_genv_safety in
         forall (U : schedule) (init_mem_source' : Memory.Mem.mem)
             (j : Values.Val.meminj) (c : Asm.state)
             (C_source : OrdinalPool.t(Sem:=SemSource))
             (C_target : OrdinalPool.t) tr
             (SIM : HybridMachine_simulation (ClightConcurSem (opt_init_mem_source p))
                                             (AsmConcurSem (opt_init_mem_target tp))) (cd : index SIM),
        match_state SIM cd j C_source init_mem_source' C_target
                    (Asm.get_mem c) ->
        (forall (n : nat) U,
            (valid SemSource) (tr, C_source, init_mem_source') U ->
            HybridCoarseMachine.csafe(Sem:=SemSource)
                                     (resources:=HybridMachine.DryHybridMachine.dryResources)
                                     (ThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
      (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
                                     (U, tr, C_source)
                                     init_mem_source' n) ->
        forall (n : nat) U ,
          (valid SemTarget) (tr, C_target, Asm.get_mem c) U ->
          HybridCoarseMachine.csafe (Sem:=SemTarget)
                                     (resources:=HybridMachine.DryHybridMachine.dryResources)
                                     (ThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
      (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
                                     (U, tr, C_target)
                                     (Asm.get_mem c) n.
    Proof.
      intros until n.
      eapply explicit_safety_csafe; eauto.      
      eapply explicit_safety_step; eauto.
      eapply csafe_explicit_safety.
      + eapply Clight_finite_branching.
      + eapply H0. 
    Qed.



    (** for the initial state, it's enough to prove csafety for the valid schedules,
        we can derive safety for all others. *)
    Lemma initial_csafe_all_schedule:
      forall  prog asm_genv_safety tr c m r,
        let SemTarget:= @X86Sem prog asm_genv_safety in
        let tp:=OrdinalPool.mkPool (Krun c) r in
        (forall U (n : nat),
            (valid SemTarget) (tr, tp, m) U ->
            HybridCoarseMachine.csafe
              (ThreadPool:=threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
              (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
              (U, nil,
               OrdinalPool.mkPool
                 (Krun c) r) m n)  ->
        forall U (n : nat),
          HybridCoarseMachine.csafe
            (ThreadPool:=threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
            (machineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
            (U, nil,
             OrdinalPool.mkPool (Krun c) r) m n.
    Proof.
      intros.
      revert U.
      induction n; try solve[econstructor].
      intros U.
      destruct U as [|i U]; [|destruct i].
      - econstructor; eauto.
      - eapply H.
        unfold safety_equivalence.valid, correct_schedule; simpl.
        intros ?????.
        simpl in cnti.
        unfold OrdinalPool.containsThread in cnti; simpl in cnti.
        clear - cnti.
        eapply semax_invariant.ssr_leP_inv in cnti.
        destruct j; simpl; [auto| omega].
      - intros.
        eapply HybridCoarseMachine.AngelSafe; simpl.
        eapply schedfail; simpl.
        * reflexivity.
        * unfold OrdinalPool.containsThread; simpl.
          intros LEQ; eapply semax_invariant.ssr_leP_inv in LEQ.
          omega.
        * assert ((valid SemTarget) (tr, tp, m) (cons 0 nil) ).
          { subst tp; auto.
          unfold safety_equivalence.valid, correct_schedule; simpl.
          intros ?????.
          simpl in cnti.
          unfold OrdinalPool.containsThread in cnti; simpl in cnti.
          clear - cnti.
          eapply semax_invariant.ssr_leP_inv in cnti.
          destruct j; simpl; [auto| omega]. }
          apply (H _ 1) in H0.
          admit. (*Should be able to pull the invariant from H0*)
        * admit. (*Should be able to pull the invariant from H0*)
        * reflexivity.
        * intros U''; eapply IHn.
    Admitted.

    
    Lemma ConcurrentCompilerSafety:
      forall (p : Clight.program) (tp : Asm.program),
        CC_correct.CompCert_compiler p = Some tp ->
        forall asm_genv_safety : Asm_core.safe_genv (@the_ge tp),
          let SemSource:= (ClightSemantincsForMachines.ClightSem (Clight.globalenv p)) in
          let SemTarget:= @X86Sem tp asm_genv_safety in
          concurrent_simulation_safety_preservation
            (Genv.init_mem (Ctypes.program_of_program p))
            (Genv.init_mem tp)
            (SemSource:= SemSource)
            (SourceThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemSource))
            (SourceMachineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
            (SemTarget :=  SemTarget)
            (TargetThreadPool:= threadPool.OrdinalPool.OrdinalThreadPool(Sem:=SemTarget))
            (TargetMachineSig:= HybridMachine.DryHybridMachine.DryHybridMachineSig)
    .
      unfold concurrent_simulation_safety_preservation; intros.
      pose proof (ConcurrentCompilerCorrectness p tp H asm_genv_safety) as SIM.
      unfold ConcurrentCompilerCorrectness_specification in SIM.
      (*Construct the initial state*)
      apply (HybridMachine_simulation.initial_setup SIM) in H1 as
          (j&cd&t_mach_state&t_mem&t_mem'&r2&(INIT_mem & INIT)&?).
      assert(INIT':= INIT).
      destruct r2; try solve[inversion INIT'].
      destruct INIT' as (c&?&?).
      subst t_mach_state; simpl in *.
      do 3 eexists; repeat split; eauto.
      eapply INIT.
      
      destruct H3 as (H21 & H22); subst.
      clear INIT H21.

      (* Now, we strip out the scheudle, until it starts with 1*)
      eapply initial_csafe_all_schedule.
      intros; eapply csafety_step; eauto.
      eapply H1.
    Qed.
    
End Concurrent_Safety.
