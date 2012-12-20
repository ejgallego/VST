Load loadpath.
Require Import 
 msl.base veric.sim veric.step_lemmas veric.base veric.expr veric.extspec
 veric.extension veric.extension_proof.

Set Implicit Arguments.

Section NullExtension.
 Variables
  (fT vT cT dT Z: Type) (** external states *)
  (csemT: CoreSemantics (Genv.t fT vT) cT mem dT) 
  (csig: ext_sig mem Z) (** client signature *)
  (genv_mapT: forall i:nat, Genv.t fT vT)
  (at_external_handled: forall c ef args sig,
    at_external csemT c = Some (ef, sig, args) -> IN ef csig = true).

 Definition cores := fun _:nat => csemT.

 Local Open Scope nat_scope.

 Definition xT := cT.
 Definition proj_core (i: nat) (s: xT) := if eq_nat_dec i 0 then Some s else None.
 Definition active := fun _:xT => 0.
 Definition runnable := fun (s: xT) => 
   match at_external csemT s, safely_halted csemT s with 
     | None, None => true
     | _, _ => false
   end.
 Definition proj_zint := fun _:xT => tt.
 Definition proj_zext := fun z: Z => z.
 Definition zmult := fun (_:unit) (z: Z) => z.
 Definition handled: list AST.external_function := nil.

 Local Hint Unfold cores proj_core active runnable proj_zint : null_unfold.

 Obligation Tactic := autounfold with null_unfold; 
  intros; try solve [eexists; eauto|congruence].
 
 Program Definition null_extension := Extension.Make 
  (fun i:nat => Genv.t (const fT i) (const vT i))
  csemT cores csig csig handled
  proj_core _  
  active _ 
  runnable _ _ _ _  
  proj_zint proj_zext zmult _ _ _.
 Next Obligation.
  revert H0; case_eq (eq_nat_dec i 0).
  intros -> _; exists s; auto.
  congruence.
 Qed.
 Next Obligation. if_tac; exists s; auto. elimtype False; apply H; auto. Qed.
 Next Obligation. 
  if_tac in H0; try congruence; inv H0; inv H.
  unfold const in *.
  destruct (at_external csemT c); try solve[congruence].
  destruct p as [[? ?] ?]. 
  right; eexists; eexists; eexists; eauto.
  destruct (safely_halted csemT c); try solve[congruence].
  solve[left; eexists; eauto].
 Qed.
 Next Obligation. inversion H; subst; eapply at_external_handled; eauto. Qed.
 Next Obligation. 
  inversion H; subst; if_tac in H; try congruence. 
  unfold const in *.
  inversion H3; subst.
  solve[rewrite H0 in H1; congruence].
 Qed.
 Next Obligation. unfold linkable; intros; inv H0; inv H1; exists x'; auto. Qed.

End NullExtension.

Section NullExtensionSafe.
 Variables
  (fT vT cT dT Z: Type) (** external states *)
  (csemT: CoreSemantics (Genv.t fT vT) cT mem dT) 
  (csig: ext_sig mem Z) (** client signature *)
  (genv_mapT: forall i:nat, Genv.t fT vT)
  (at_external_handled: forall c ef args sig,
    at_external csemT c = Some (ef, sig, args) -> IN ef csig = true)
  (ge: Genv.t fT vT).

 Import ExtensionSafety.

 Local Hint Unfold cores proj_core active runnable proj_zint : null_unfold.

 Obligation Tactic := autounfold with null_unfold;
  intros; try solve [eexists; eauto|congruence].

 Lemma null_extension_safe (csem_fun: corestep_fun csemT): 
  safe_extension ge (fun _:nat => ge) (null_extension csemT csig at_external_handled).
 Proof.
 destruct (ExtensionSafety (null_extension csemT csig at_external_handled) 
  ge (fun _:nat => ge)) as [PF].
 apply PF.
 constructor; autounfold with null_unfold in *.

 (*1*) intros until m'; intros H1 H4 H5 H6. 
 assert (H3:True) by auto.
 unfold Extension.proj_core in H4; simpl in H4.
 generalize H4 as H4'; intro.
 unfold proj_core in H4; if_tac in H4; try solve[congruence].
 inversion H4 as [H7]; rewrite H7 in *; clear H7 H4.
 rewrite H in *; clear H.
 unfold Extension.proj_core; simpl; unfold proj_core.
 simpl in H5.
 f_equal; generalize (csem_fun _ _ _ _ _ _ _ H5 H6); inversion 1; auto.
 simpl in H1|-*.
 unfold proj_zint, all_safe in *.
 intros until c0; intros H0.
 assert (H8:True) by auto.
 inversion H0 as [H7]. simpl in H0. rewrite H7 in *; clear H0.
 unfold proj_core in H7.
 if_tac in H7; try solve[congruence].
 rewrite <-H0 in *; clear H; inversion H7 as [H].
 rewrite H in *; clear H7 H.
 solve[eapply safe_corestep_forward; eauto].

 (*2*) intros until c; intros H1 H3 H5.
 assert (H4:True) by auto.
 spec H1 (active s) c H5.
 simpl in H5.
 simpl in H3; unfold runnable in H3; simpl in H3.
 case_eq (at_external csemT s).
 intros [[ef sig] args] H6.
 rewrite H6 in H3.
 simpl in H5; unfold proj_core in H5; simpl in H5; inversion H5; subst.
 congruence.
 intros H6.
 rewrite H6 in H3.
 unfold proj_core in H5.
 if_tac in H5; try congruence.
 inv H5.
 case_eq (safely_halted csemT c); try congruence.
 intros rv Hsafe.
 rewrite Hsafe in H3.
 congruence.
 unfold const in *. 
 simpl in H1.
 rewrite H6 in H1.
 intros Hsafe; rewrite Hsafe in H1.
 destruct H1 as [c' [m' [H1 H7]]].
 solve[exists c'; exists c'; exists m'; split; auto].

 (*3*) intros until x; intros H2 H3 H4 H5 H6 H7 H8.
 assert (H1:True) by auto.
 apply ListSet.set_mem_correct1 in H4.
 unfold handled, ListSet.set_In in H4.
 solve[inversion H4].

 (*4*) intros until m; intros H1 H2 H3.
 simpl in H2; unfold runnable in H2.
 inversion H3; subst.
 unfold compose in H0;  simpl in H0.
 rewrite H0 in H2.
 case_eq (safely_halted csemT s); intros; try solve[congruence].
 rewrite H in H2.
 right; exists v; auto.
 solve[rewrite H in H2; congruence].

 (*5*) intros until rv; intros H2 H3 H4.
 unfold const in *.
 simpl.
 apply corestep_not_halted in H4.
 simpl in H2; inversion H2; subst.
 unfold proj_core in H0.
 solve[if_tac in H0; try solve[congruence]].

 (*6*) intros until c; inversion 1; subst.
 intros H4 H5; intros until c0; intros H6; split.
 intros H8.
 assert (H7:True) by auto.
 simpl in H8; unfold proj_core in H8; simpl in H8; inversion H8; subst.
 simpl; unfold proj_core; simpl.
 simpl in H6; unfold active in H6.
 if_tac; auto.
 exfalso; apply H6; auto.
 intros n z z' H8.
 assert (H7:True) by auto.
 simpl in H8; unfold proj_core in H8; simpl in H8.
 simpl in H6; unfold active in H6; simpl in H6.
 if_tac in H8; auto.
 inversion H8; subst.
 exfalso; apply H6; auto.
 solve[congruence].

 (*7*) intros until args; intros H1.
 solve[exists s; split; auto].

 (*8*) intros until Q.
 unfold const in *.
 intros H2 H3 H4 H5 H6.
 assert (H1:True) by auto.
 intros H12; simpl; exists c'; split3; auto.
 simpl in H2; unfold proj_core in H2.
 if_tac in H2; try solve[congruence].

 (*9*) intros until Q; intros H2 H3 H4 H5 H6 H7 H70 [H8 H9]; 
 intros until c0; intros H10; split.
 intros H12.
 assert (H11:True) by auto.
 simpl in H12; unfold proj_core in H12; simpl in H12.
 if_tac in H12; auto.
 simpl in H9; unfold proj_core in H9; simpl in H9.
 simpl in H10; unfold active in H10; simpl in H10.
 exfalso; apply H10; auto.
 congruence.
 intros ge'  n H12.
 simpl in H10, H12.
 unfold active in H10; unfold proj_core in H12.
 if_tac in H12.
 exfalso; auto.
 congruence.
 Qed.

End NullExtensionSafe.

 Lemma null_core_compatible: forall F V C D Z (ge: Genv.t F V) 
         (csem: CoreSemantics (Genv.t F V) C mem D) (csig: ext_sig mem Z) PF
         (csem_fun: corestep_fun csem),
   core_compatible ge (fun _:nat => ge) (null_extension csem csig PF).
 Proof.
 intros until PF.
 intros CSEM_FUN.
 constructor; simpl; auto.
 intros until c; intros H1 H2 H3.
 exists s'.
 simpl; unfold cores, active; simpl; split; auto.
 simpl in H2.
 solve[inv H2; auto].
 
 intros until m'; intros H1 H2 H3.
 unfold active, cores in *.
 split; auto.
 unfold proj_core; auto.
 if_tac; auto.
 unfold proj_core in H1.
 if_tac in H1; try congruence.
 inv H1.
 generalize (CSEM_FUN _ _ _ _ _ _ _ H2 H3).
 inversion 1; subst; auto.
 solve[elimtype False; auto].

 intros until m'; intros H1 H2.
 exists c'.
 unfold cores, active in H2.
 unfold proj_core in H1.
 solve[if_tac in H1; try congruence].

 intros until m'; intros H1 H2 H3; intros j; intros H4.
 unfold cores, active in *.
 unfold proj_core.
 if_tac; auto.
 solve[elimtype False; auto].

 intros until n; intros H1 H2 H3 j H4.
 unfold active, cores in *.
 unfold proj_core.
 if_tac; auto.
 solve[elimtype False; auto].

 intros until retv; intros H1 H2.
 exists c'.
 unfold cores, active in H1, H2.
 inv H1.
 solve[split; auto].

 intros s s' retv H1 j H2.
 unfold proj_core; auto.
 unfold active in H2.
 if_tac; auto.
 solve[elimtype False; auto].

 intros until args; intros H1.
 exists s.
 unfold active, cores, proj_core.
 solve[split; auto].
 Qed.

 (*MOVE ELSEWHERE*)
 Lemma genvs_domain_eq_refl: forall F V (ge: Genv.t F V), genvs_domain_eq ge ge.
 Proof. solve[intros F V ge; unfold genvs_domain_eq; split; intro b; split; auto]. Qed.

Section NullExtensionCompilable.
 Variables 
  (fS vS fT vT cS cT dS dT Z: Type) 
  (csig: ext_sig mem Z)
  (init_world: Z)
  (entry_points: list (val*val*signature))
  (csemS: CoreSemantics (Genv.t fS vS) cS mem dS)
  (csemT: CoreSemantics (Genv.t fT vT) cT mem dT)
  (at_external_handledS: forall c ef args sig,
    at_external csemS c = Some (ef, sig, args) -> IN ef csig = true)
  (at_external_handledT: forall c ef args sig,
    at_external csemT c = Some (ef, sig, args) -> IN ef csig = true).

 Variables (geS: Genv.t fS vS) (geT: Genv.t fT vT).

 Definition E_S: 
  Extension.Sig (fun i : nat => Genv.t ((fun _ => fS) i) ((fun _ => vS) i))
   (fun _ : nat => cS) unit csemS (fun _:nat => csemS) csig csig handled := 
  null_extension csemS csig at_external_handledS.
 Definition E_T: 
  Extension.Sig (fun i : nat => Genv.t ((fun _ => fT) i) ((fun _ => vT) i))
   (fun _ : nat => cT) unit csemT (fun _:nat => csemT) csig csig handled := 
  null_extension csemT csig at_external_handledT.

 Import Sim_inj_exposed.
 Import ExtensionCompilability2.

 Variable core_data: Type.
 Variable match_state: core_data -> meminj -> cS -> mem -> cT -> mem -> Prop. 
 Variable core_ord: core_data -> core_data -> Prop.
 Variable core_simulation: Forward_simulation_inject dS dT csemS csemT 
   geS geT entry_points core_data match_state core_ord.
 Variable core_simulationsRG: forall i:nat, 
   RelyGuaranteeSimulation.Sig csemS csemT match_state.
 Variable threads_max: nat.
 Variable threads_max_nonzero: (O < threads_max)%nat. (*Required by defn. of core_ords*)

 Variable match_state_runnable: 
  forall cd j s1 m1 s2 m2,
  match_state cd j s1 m1 s2 m2 -> 
  Extension.runnable E_S s1=Extension.runnable E_T s2.

 Lemma null_extension_compilable: 
   corestep_fun csemS -> corestep_fun csemT -> genvs_domain_eq geS geT -> 
   CompilableExtension.Sig csemS csemT geS geT entry_points.
 Proof.
 (*SOLVED BY econstructor; eauto.  WE'LL USE THE PROVIDED LEMMAS INSTEAD.*)
 intros H1 H2 H3.
 destruct (@ExtensionCompilability
   _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ 
   csemS csemT csemS csemT csig csig handled 
   geS geT geS geT E_S E_T entry_points core_data match_state core_ord threads_max)
  as [LEM].
 apply LEM; auto.
 solve[intros i; unfold const; apply genvs_domain_eq_refl; auto].
 solve[intros i; unfold const; apply genvs_domain_eq_refl; auto].
 unfold E_S, const.
 solve[apply (null_core_compatible geS csig at_external_handledS H1)].
 unfold E_T, const.
 solve[apply (null_core_compatible geT csig at_external_handledT H2)].

 constructor.
 intros until j'; intros H4 H5 H6 H7 H8 H9 H10 H11 PROJ1' PROJ2' MATCH12'.
 unfold const in MATCH12'.
 inv PROJ1'; inv PROJ2'.
 solve[eapply match_state_runnable; eauto].

 intros until j; intros H4 H5 H6 H7 H8 H9 H10 H11 H12 H13 H14 H15.
 destruct core_simulation; unfold const; simpl.
 destruct H10 as [? [? MATCH]].
 specialize (MATCH O s1).
 spec MATCH; auto.
 destruct MATCH as [_s2 [PROJ MATCH]].
 inv PROJ.
 specialize (core_diagram0 s1 m1 s1' m1' H15 (cd O) _s2 j m2). 
 spec core_diagram0; auto.
 destruct core_diagram0 as [s2' [m2' [cd' [j' [? [? [? ?]]]]]]].
 exists s2'; exists m2'; exists (fun _ => cd'); exists j'.
 split3; auto.
 split; auto.
 split3; auto.
 solve[eapply match_state_runnable; eauto].
 intros i _s1'; simpl; unfold proj_core; intros PROJ.
 if_tac in PROJ; try congruence.
 inv PROJ.
 solve[exists s2'; auto].
 destruct H18.
 solve[left; auto].
 destruct H18 as [A B].
 right; split; auto.
 unfold CompilabilityInvariant.core_ords.
 exists O. 
 split; auto.
 split; auto.
 solve[intros k; inversion 1].

 intros; simpl in H5; unfold proj_core, active in H5.
 if_tac in H5; try congruence.
 solve[inv H5; auto].

 intros; unfold E_S, E_T in *; simpl in *.
 unfold CompilabilityInvariant.match_states in H0.
 destruct H0 as [_ [_ MATCH]].
 specialize (MATCH O s1).
 spec MATCH; auto.
 destruct MATCH as [c2 [PROJ MATCH]].
 inv PROJ.
 unfold const in MATCH.
 destruct core_simulation.
 generalize MATCH as MATCH'; intro.
 eapply core_at_external0 in MATCH; eauto.
 destruct MATCH as [INJ [PRES [vals2 [? [? EXT]]]]].
 assert (Hrv1: exists retv1', retv1 = Some retv1'). admit. (*Update sim.v to allow retv=None*)
 assert (Hrv2: exists retv2', retv2 = Some retv2'). admit. (*Update sim.v to allow retv=None*)
 destruct Hrv1 as [retv1' XX]; rewrite XX in *.
 destruct Hrv2 as [retv2' YY]; rewrite YY in *.
 apply core_after_external0 
  with (j' := j') (e := ef) (ret1 := retv1') (m1' := m1') (m2' := m2') (ret2 := retv2')
       (vals1 := args1) (ef_sig := sig) in MATCH'; auto.
 destruct MATCH' as [? [? [? [? [? ?]]]]].
 rewrite H15 in H18; inv H18.
 rewrite H16 in H19; inv H19.
 solve[eapply match_state_runnable; eauto].
 admit. (*Update sim.v to allow retv=None; add commented line in extension:after_external_runnable*)
 
 intros; destruct core_simulation.
 destruct (core_initial0 v1 v2 sig H vals1 s1 m1 j vals2 m2 H0 H4 H5 H6) 
  as [cd [s2 [H7 H8]]].
 exists (fun _ => cd); exists s2; split; auto. split; auto.
 split; [solve[eapply match_state_runnable; eauto]|].
 intros i c1 H9; exists s2; split; auto.
 simpl in H9; unfold proj_core in H9|-*; if_tac in H9; try congruence.
 solve[inv H9; split; auto].
 simpl in H9; unfold proj_core in H9.
 if_tac in H9; try congruence.
 solve[inv H9; auto].

 intros until v1; intros MATCH12 HALT.
 unfold CompilabilityInvariant.match_states, const in MATCH12.
 destruct MATCH12 as [? [? MATCH12]].
 specialize (MATCH12 O c1).
 spec MATCH12; auto.
 destruct MATCH12 as [c2' [PROJ MATCH12]].
 simpl in PROJ; unfold proj_core in PROJ; inv PROJ.
 destruct core_simulation.
 solve[eapply core_halted0 in HALT; eauto].

 intros; destruct core_simulation.
 apply corestep_not_halted in H6.
 simpl in H0; unfold proj_core, active in H0.
 if_tac in H0; try congruence.
 solve[inv H0; simpl in H5; unfold const in H5; rewrite H5 in H6; congruence].
 Qed.

End NullExtensionCompilable.
