(* Tested with coq 8.5pl1 *)

Require Import Basics.
Require Import Reals.
Require Import List.
Require Import Ensembles.
Require Import Coq.Logic.FunctionalExtensionality.
Require Import Coq.Logic.ProofIrrelevance.
Require Import Coq.Program.Basics.
Require Import Coq.Program.Equality.
Require Import Coq.Setoids.Setoid.
Require Import nnr.
Require Import syntax.
Require Import utils.
Require Import Coq.Classes.Morphisms.
Require determinism.
Import EqNotations.

Opaque π.

Local Open Scope R.

Definition Event X := X -> bool.

Definition eval_dec :
  forall {e τ},
    (TC · ⊢ e : τ) ->
    forall σ,
      (existsT! vw : (Val * R+), let (v, w) := vw in EVAL σ ⊢ e ⇓ v, w) +
      ((existsT vw : (Val * R+), let (v, w) := vw in EVAL σ ⊢ e ⇓ v, w) -> False)
  := @determinism.eval_dec.

Definition big_preservation :
  forall {e τ v w σ},
    (TC · ⊢ e : τ) ->
    (EVAL σ ⊢ e ⇓ v, w) ->
    (TC · ⊢ v : τ)
  := @determinism.big_preservation.

Definition ev {e τ} (He : TC · ⊢ e : τ) σ : option (WT_Val τ) :=
  match eval_dec He σ with
  | inl (existT _ (v, w) (evl, _)) =>
    Some (mk_WT_Val _ (big_preservation He evl))
  | inr _ => None
  end.

Definition ew {e τ} (He : TC · ⊢ e : τ) σ : R+ :=
  match eval_dec He σ with
  | inl (existT _ (v, w) _) => w
  | inr _ => nnr_0
  end.

Definition resist_folding {A} (x : A) := x.

Definition ifte {X} (a : bool) (b c : X) := if a then b else c.
Definition Indicator {X} (b : Event X) : X -> R+ := fun x => ifte (b x) nnr_1 nnr_0.


Definition eval_in {e τ} (He : TC · ⊢ e : τ) (A : Event (WT_Val τ)) σ : R+ :=
  option0 (Indicator A <$> ev He σ) [*] ew He σ.

Definition Meas A := (Event A -> R+).
Axiom μEntropy : Meas Entropy.

Axiom Integration : forall {A}, (A -> R+) -> Meas A -> R+.
(* Notation "'∫' fx ';' μ ( 'd' x )" := (Integration (fun x => fx) μ). *)

Ltac integrand_extensionality x :=
  match goal with
  | [ |- Integration ?f ?μ = Integration ?g ?μ] => f_equal; extensionality x
  | _ => fail "not an equality between integrals on the same measure"
  end.

Axiom Integration_linear :
  forall {A} (μ : Meas A) (s0 s1 : R+) (f0 f1 : A -> R+),
    s0 [*] Integration f0 μ [+] s1 [*] Integration f1 μ =
    Integration (fun x => s0 [*] f0 x [+] s1 [*] f1 x) μ.

Lemma Integration_linear_mult_r :
  forall {A} (μ : Meas A) (s : R+) (f : A -> R+),
    Integration f μ [*] s =
    Integration (fun x => f x [*] s) μ.
Proof.
  intros.
  nnr.
  simpl.
  rewrite Rmult_comm.
  rewrite <- Rplus_0_r at 1.
  rewrite <- Rmult_0_l with (r := _r (Integration (const nnr_0) μ)).
  replace 0 with (_r nnr_0) by auto.

  replace (_ + _) with
  (_r (s [*] Integration f μ [+] nnr_0 [*] Integration (const nnr_0) μ))
    by auto.
  f_equal.
  rewrite Integration_linear.
  integrand_extensionality x.
  nnr.
Qed.

Lemma Integration_linear_mult_l :
  forall {A} (μ : Meas A) (s : R+) (f : A -> R+),
    s [*] Integration f μ =
    Integration (fun x => s [*] f x) μ.
Proof.
  intros.
  rewrite nnr_mult_comm.
  rewrite Integration_linear_mult_r.
  integrand_extensionality x.
  nnr.
Qed.

Definition bool_of_dec {A B} : sumbool A B -> bool :=
  fun x => if x then true else false.

Axiom lebesgue_measure : Meas R.
Axiom lebesgue_measure_interval :
  forall (r : R+),
    lebesgue_measure (fun x => bool_of_dec (r [>] x)) = r.

Axiom riemann_def_of_lebesgue_integration :
  forall {A} μ (f : A -> R+),
    Integration f μ =
    Integration
      (fun t => μ (fun x => bool_of_dec (f x [>] t)))
      lebesgue_measure.

Axiom integration_of_indicator :
  forall {A}
         (m : Meas A)
         (f : Event A),
    Integration (fun x => Indicator f x) m = m f.

Definition μ {e τ} (He : TC · ⊢ e : τ) : Meas (WT_Val τ) :=
  fun V => Integration (fun σ => eval_in He V σ) μEntropy.

Definition A_rel' (τ : Ty) (V_rel_τ : Val -> Val -> Type)
        (A0 A1 : Event Val) :=
  forall v0 v1 (Hv : V_rel_τ v0 v1),
    (A0 v0 = (* iff *) A1 v1).

Definition E_rel' (τ : Ty) (V_rel_τ : Val -> Val -> Prop) (e0 e1 : Expr) : Prop :=
  exists (He0 : (TC · ⊢ e0 : τ))
         (He1 : (TC · ⊢ e1 : τ)),
  forall A0 A1,
    A_rel' τ V_rel_τ A0 A1 ->
    μ He0 A0 = μ He1 A1.

Definition V_rel_real (v0 v1 : Val) : Prop :=
  match (v0 : Expr), (v1 : Expr) with
  | e_real r0, e_real r1 => v0 = v1
  | _, _ => False
  end.

Definition V_rel_arrow
           (τa : Ty) (τr : Ty)
           (V_rel_a : Val -> Val -> Prop)
           (V_rel_r : Val -> Val -> Prop)
           (v0 v1 : Val) : Prop
  := match (v0 : Expr), (v1 : Expr) with
     | e_lam τa'0 body0, e_lam τa'1 body1  =>
       (τa = τa'0) ⨉ (τa = τa'1) ⨉
       exists (tc_body0 : (TC (extend · τa) ⊢ body0 : τr))
              (tc_body1 : (TC (extend · τa) ⊢ body1 : τr)),
       forall {va0 va1 : WT_Val τa},
           V_rel_a va0 va1 ->
           E_rel' τr V_rel_r body0.[(va0 : Expr)/] body1.[(va1 : Expr)/]
     | _, _ => False
     end.

(* Reserved Notation "'VREL' v0 , v1 ∈ V[ τ ]" *)
(*          (at level 69, v0 at level 99, v1 at level 99, τ at level 99). *)
Fixpoint V_rel τ : Val -> Val -> Prop :=
  match τ with
  | ℝ => V_rel_real
  | τa ~> τr => V_rel_arrow τa τr (V_rel τa) (V_rel τr)
  end.

(* Notation "'VREL' v0 , v1 ∈ V[ τ ]" := (V_rel τ v0 v1). *)

Definition A_rel τ := A_rel' τ (V_rel τ).
Definition E_rel τ := E_rel' τ (V_rel τ).

(* Notation "'EREL' e0 , e1 ∈ E[ τ ]" := *)
(*   (E_rel τ e0 e1) *)
(*     (at level 69, e0 at level 99, e1 at level 99, τ at level 99). *)
(* Notation "'AREL' A0 , A1 ∈ A[ τ ]" := *)
(*   (A_rel τ A0 A1) *)
(*     (at level 69, A0 at level 99, A1 at level 99, τ at level 99). *)


Definition G_rel {Γ : Env Ty} {ρ0 ρ1 : WT_Env Γ} : Type :=
  forall {x v0 v1 τ},
    lookup Γ x = Some τ ->
    lookup ρ0 x = Some v0 ->
    lookup ρ1 x = Some v1 ->
    V_rel τ v0 v1.

Arguments G_rel _ _ _ : clear implicits.
(* Notation "'GREL' ρ0 , ρ1 ∈ G[ Γ ]" := *)
(*   (G_rel Γ ρ0 ρ1) *)
(*     (at level 69, ρ0 at level 99, ρ1 at level 99, Γ at level 99). *)

(* Definition related_expr (Γ : Env Ty) (e : Expr) (τ : Ty) : Type := *)
(*   {He : (TC Γ ⊢ e : τ) & *)
(*         forall {ρ} (Hρ : dGREL ρ ∈ G[Γ]), *)
(*           (dEREL (mk_config (dG_rel_modeling Hρ) He) ∈ E[τ])}. *)

Lemma G_rel_nil : G_rel · WT_nil WT_nil.
Proof.
  repeat intro.
  discriminate.
Qed.

Record related_exprs (Γ : Env Ty) (τ : Ty) (e0 e1 : Expr) : Type :=
  mk_related_exprs
  { rel_expr_He0 : (TC Γ ⊢ e0 : τ);
    rel_expr_He1 : (TC Γ ⊢ e1 : τ);
    rel_expr_erel {ρ0 ρ1} (Hρ : G_rel Γ ρ0 ρ1) :
      (E_rel τ e0.[subst_of_WT_Env ρ0] e1.[subst_of_WT_Env ρ1])
  }.

Arguments mk_related_exprs {_ _ _ _} _ _ _.

Notation "'EXP' Γ ⊢ e0 ≈ e1 : τ" :=
  (related_exprs Γ τ e0 e1)
    (at level 69, e0 at level 99, e1 at level 99, no associativity).

Definition dirac {A} (v : A) : Meas A :=
  fun e => Indicator e v.

Definition is_dirac {A} (v : A) (m : Meas A) : Prop :=
  m = dirac v.


Ltac decide_eval' exp v w e u :=
  let not_ex := fresh "not_ex" in
  destruct (eval_dec exp) as [[[v w] [e u]] | not_ex];
  [|
   try (contradict not_ex; eexists (_, _); repeat constructor; eassumption);
   try solve [nnr]].
Tactic Notation "decide_eval" uconstr(exp) "as"
       "[" ident(v) ident(w) ident(e) ident(u) "]"
  := (decide_eval' exp v w e u).

(* Ltac generalize_inhabit := *)
(*   match goal with *)
(*   | [ |- context[inhabits ?t]] => generalize (inhabits t); intros ?i *)
(*   end. *)

(* Ltac irrelevate_inhabit := *)
(*   match goal with *)
(*     [ H0 : inhabited ?x, H1 : inhabited ?x |- _ ] => *)
(*     pose proof (proof_irrelevance _ H0 H1); subst H0 *)
(*   end. *)

(* Ltac inhabited_irrelevance := progress (repeat generalize_inhabit; repeat irrelevate_inhabit). *)


Axiom int_const_entropy :
  forall (v : R+)
         (f : Entropy -> R+),
     (forall x, f x = v) ->
     Integration f μEntropy = v.

Lemma val_of_pure {e τ} :
  (TC · ⊢ e : τ) ->
  is_pure e ->
  is_val e.
Proof.
  intros.
  destruct e; try contradiction H; trivial.
  inversion X.
  discriminate.
Qed.

Definition WT_Val_of_pure {e τ} (He : (TC · ⊢ e : τ)) (Hp : is_pure e)
  : WT_Val τ := @mk_WT_Val _ (mk_Val e (val_of_pure He Hp)) He.

Lemma pure_is_atomic {e τ} A
      (He : (TC · ⊢ e : τ))
      (Hpure : is_pure e) :
  (fun σ => eval_in He A σ) =
  (fun σ => Indicator A (WT_Val_of_pure He Hpure)).
Proof.
  extensionality σ.

  pose (WT_Val_of_pure He Hpure) as v'.
  assert (e = v') by auto.
  clearbody v'.
  subst.

  unfold eval_in, ev, ew.

  decide_eval _ as [v w ex u]; simpl in *. {
    inversion ex; subst; try absurd_Val.
    nnr.
    unfold nnr_mult.
    simpl.
    rewrite Rmult_1_r.
    apply Val_eq in H0.
    subst.
    destruct (v' : Val) using Val_rect. {
      inversion He; subst.
      repeat f_equal.
      apply WT_Val_eq.
      auto.
    } {
      inversion He; subst.
      repeat f_equal.
      apply WT_Val_eq.
      auto.
    }
  }
Qed.

Lemma pure_is_dirac {e τ}
      (He : TC · ⊢ e : τ)
      (Hpure : is_pure e) :
  μ He = dirac (WT_Val_of_pure He Hpure).
Proof.

  extensionality A.
  unfold μ, dirac; simpl.
  rewrite (pure_is_atomic A He Hpure).
  apply int_const_entropy; intro σ.
  auto.
Qed.

Lemma compat_real Γ r :
  (EXP Γ ⊢ e_real r ≈ e_real r : ℝ).
Proof.
  refine (mk_related_exprs (TCReal _) (TCReal _) _).
  intros ρ0 ρ1 Hρ.
  simpl.

  exists (TCReal r).
  exists (TCReal r).
  intros A0 A1 HA.

  rewrite (pure_is_dirac (TCReal r) I).

  unfold dirac, Indicator; simpl.
  f_equal.
  apply HA.
  reflexivity.
Qed.

Lemma compat_var Γ x τ :
  lookup Γ x = Some τ ->
  EXP Γ ⊢ e_var x ≈ e_var x : τ.
Proof.
  intros Γx.
  refine (mk_related_exprs (TCVar _) (TCVar _) _); auto.
  intros ρ0 ρ1 Hρ.

  simpl.

  destruct (env_search (WT_Env_tc ρ0) Γx) as [v0 ρ0x].
  destruct (env_search (WT_Env_tc ρ1) Γx) as [v1 ρ1x].
  rewrite (subst_of_WT_Env_lookup ρ0x).
  rewrite (subst_of_WT_Env_lookup ρ1x).
  exists (WT_Val_tc v0).
  exists (WT_Val_tc v1).

  intros A0 A1 HA.

  specialize (Hρ _ _ _ _ Γx ρ0x ρ1x).

  assert (forall v : Val, is_pure v). {
    intros.
    destruct v as [[]]; try contradiction; constructor.
  }

  rewrite 2 (pure_is_dirac (WT_Val_tc _) (H _)).
  unfold dirac, Indicator; simpl.
  f_equal.
  apply HA.

  rewrite <- (@Val_eq v0) at 1 by auto.
  rewrite <- (@Val_eq v1) by auto.
  auto.
Qed.

Lemma extend_grel {Γ ρ0 ρ1 τ}
      (v0 v1 : WT_Val τ)
      (Hρ : G_rel Γ ρ0 ρ1)
      (Hv : V_rel τ v0 v1)
  : G_rel (extend Γ τ) (extend_WT_Env ρ0 v0) (extend_WT_Env ρ1 v1).
Proof.
  intros x v0' v1' τ' Γx ρ0x ρ1x.
  destruct x. {
    simpl in *.
    inversion Γx.
    inversion ρ0x.
    inversion ρ1x.
    subst.
    apply Hv.
  } {
    simpl in *.
    eapply Hρ; eauto.
  }
Qed.

Lemma compat_lam Γ body0 body1 τa τr :
  (EXP (extend Γ τa) ⊢ body0 ≈ body1 : τr) ->
  (EXP Γ ⊢ e_lam τa body0 ≈ e_lam τa body1 : (τa ~> τr)).
Proof.
  intros Hbody.
  destruct Hbody as [Hbody0 Hbody1 Hbodies]; simpl in *.
  refine (mk_related_exprs (TCLam Hbody0) (TCLam Hbody1) _).
  intros ρ0 ρ1 Hρ.

  pose proof body_subst ρ0 Hbody0 as Hbody0'.
  pose proof body_subst ρ1 Hbody1 as Hbody1'.

  exists (TCLam Hbody0').
  exists (TCLam Hbody1').
  intros A0 A1 HA.

  (* can't rewrite these directly, who knows why? *)
  enough (dirac (WT_Val_of_pure (TCLam Hbody0') I) A0 =
          dirac (WT_Val_of_pure (TCLam Hbody1') I) A1). {
    rewrite <- 2 (pure_is_dirac (TCLam _) I) in H.
    exact H.
  }

  unfold dirac, Indicator; simpl.
  f_equal.
  apply HA.

  split; auto.
  exists Hbody0'.
  exists Hbody1'.

  intros va0 va1 Hva.

  specialize (Hbodies _ _ (extend_grel va0 va1 Hρ Hva)).
  autosubst.
Qed.

Axiom prod_meas : forall {A B}, Meas A -> Meas B -> Meas (A * B).

Lemma tonelli_1 :
  forall {A B} (f : A -> B -> R+) (μx : Meas A) (μy : Meas B),
    Integration (fun x => Integration (fun y => f x y) μy) μx =
    Integration (fun xy => f (fst xy) (snd xy)) (prod_meas μx μy).
Admitted.

Lemma tonelli_2 :
  forall {A B} (f : A -> B -> R+) (μx : Meas A) (μy : Meas B),
    Integration (fun xy => f (fst xy) (snd xy)) (prod_meas μx μy) =
    Integration (fun y => Integration (fun x => f x y) μx) μy.
Admitted.

Inductive SigmaFinite : forall {A}, Meas A -> Prop :=
| ent_finite : SigmaFinite μEntropy
| leb_finite : SigmaFinite lebesgue_measure.

Lemma tonelli_3 :
  forall {A B} (f : A -> B -> R+) (μx : Meas A) (μy : Meas B),
    SigmaFinite μx ->
    SigmaFinite μy ->
    Integration (fun x => Integration (fun y => f x y) μy) μx =
    Integration (fun y => Integration (fun x => f x y) μx) μy.
Admitted.

Definition preimage {A B C} (f : A -> B) : (B -> C) -> (A -> C) :=
  fun eb a => eb (f a).

Lemma lemma_3 :
  forall {X}
         (M : Event X -> Event X -> Prop)
         (μ0 μ1 : Meas X)
         (μs_aggree : forall A0 A1, M A0 A1 -> μ0 A0 = μ1 A1)
         (f0 f1 : X -> R+)
         (f_is_M_measurable :
            forall (B : Event R+),
              M (preimage f0 B) (preimage f1 B)),
    Integration f0 μ0 = Integration f1 μ1.
Proof.
  intros.
  rewrite riemann_def_of_lebesgue_integration.
  apply eq_sym.
  rewrite riemann_def_of_lebesgue_integration.
  apply eq_sym.

  integrand_extensionality t.
  apply μs_aggree.

  specialize (f_is_M_measurable (fun fx => bool_of_dec (fx [>] t))).

  apply f_is_M_measurable.
Qed.

Axiom lemma_9 : forall (g : Entropy -> Entropy -> R+),
    Integration (fun σ => g (πL σ) (πR σ)) μEntropy =
    Integration (fun σL => Integration (fun σR => g σL σR) μEntropy) μEntropy.

Lemma pick_3_and_waste : forall (g : Entropy -> Entropy -> Entropy -> Entropy -> R+),
    Integration (fun σ => g (π 0 σ) (π 1 σ) (π 2 σ) (πR (πR (πR σ)))) μEntropy =
    Integration
      (fun σ0 =>
         Integration
           (fun σ1 =>
              Integration
                (fun σ2 =>
                   Integration
                     (fun σ3 =>
                        g σ0 σ1 σ2 σ3)
                     μEntropy)
                μEntropy)
           μEntropy)
      μEntropy.
Proof.
  intros.

  evar (x : Entropy -> R+).
  replace (Integration (fun σ0 => Integration _ _) _)
  with (Integration x μEntropy).
  shelve. {
    integrand_extensionality σ0.

    evar (y : Entropy -> R+).
    replace (Integration _ _)
    with (Integration y μEntropy).
    shelve. {
      integrand_extensionality σ1.

      rewrite <- lemma_9.
      subst y.
      reflexivity.
    }
    Unshelve.
    shelve.
    shelve.
    subst y.
    rewrite <- lemma_9.
    subst x.
    reflexivity.
  }
  Unshelve.
  subst x.
  rewrite <- lemma_9.
  simpl.
  auto.
Qed.

Lemma pick_3_entropies : forall (g : Entropy -> Entropy -> Entropy -> R+),
    Integration (fun σ => g (π 0 σ) (π 1 σ) (π 2 σ)) μEntropy =
    Integration
      (fun σ0 =>
         Integration
           (fun σ1 =>
              Integration
                (fun σ2 =>
                   g σ0 σ1 σ2)
                μEntropy)
           μEntropy)
      μEntropy.
Proof.
  intros.
  pose proof pick_3_and_waste (fun (σ0 σ1 σ2 σR : Entropy) => g σ0 σ1 σ2).
  simpl in *.
  rewrite H.

  integrand_extensionality σ0.
  integrand_extensionality σ1.
  integrand_extensionality σ2.
  erewrite int_const_entropy; auto.
Qed.

Lemma pick_2_entropies : forall (g : Entropy -> Entropy -> R+),
    Integration (fun σ => g (π 0 σ) (π 1 σ)) μEntropy =
    Integration (fun σ0 => Integration (fun σ1 => g σ0 σ1) μEntropy) μEntropy.
Proof.
  intros.
  pose proof pick_3_entropies (fun (σ0 σ1 σ2 : Entropy) => g σ0 σ1).
  simpl in *.
  rewrite H.

  integrand_extensionality σ0.
  integrand_extensionality σ1.
  erewrite int_const_entropy; auto.
Qed.

Theorem theorem_15 :
  forall {e τ}
    (He : TC · ⊢ e : τ)
    (f : WT_Val τ -> R+),
      Integration f (μ He) =
      Integration (fun σ => option0 (f <$> ev He σ) [*] ew He σ) μEntropy.
Proof.
  intros.

  unfold μ.

  rewrite riemann_def_of_lebesgue_integration.
  rewrite tonelli_3; try constructor.
  unfold eval_in.

  setoid_rewrite <- Integration_linear_mult_r.

  f_equal.
  extensionality σ.

  generalize (ew He σ) as w, (ev He σ) as v.
  intros.

  f_equal.
  induction v; simpl. {
    pose proof @integration_of_indicator.
    unfold Indicator in *.
    rewrite H.
    apply lebesgue_measure_interval.
  } {
    replace (fun _ => nnr_0) with (fun _ : R => nnr_0 [*] nnr_0)
      by (extensionality z; nnr; apply Rmult_0_l).
    rewrite <- Integration_linear_mult_r.
    nnr.
  }
Qed.

Definition ensemble_of_event {X} : Event X -> Ensemble X :=
  fun A x => A x = true.

Definition at_most_one {A} (P : A -> Prop) :=
  forall x, P x -> (forall x', P x' -> x = x').

Lemma option_map_compose {A B C} (f : B -> C) (g : A -> B) (o : option A) :
  f <$> (g <$> o) = (f ∘ g) <$> o.
Proof.
  destruct o; reflexivity.
Qed.

Definition plus_in (A : Event (WT_Val ℝ)) (v v' : WT_Val ℝ) : R+ :=
  match (v : Expr), (v' : Expr) with
  | e_real r, e_real r' =>
    Indicator A (v_real (r + r'))
  | _, _ => nnr_0
  end.

Lemma by_theorem_15_plus {el er} A
  (Hel : TC · ⊢ el : ℝ)
  (Her : TC · ⊢ er : ℝ) :
    Integration (fun σ => eval_in (TCPlus Hel Her) A σ) μEntropy =
    Integration (fun vl =>
    Integration (fun vr =>
                   plus_in A vl vr
                ) (μ Her)
                ) (μ Hel).
Proof.
  setoid_rewrite theorem_15; eauto.
  setoid_rewrite theorem_15; eauto.

  replace (Integration _ μEntropy)
  with (Integration
          (fun σ0 =>
             Integration
               (fun σ1 =>
                  option0 (plus_in A <$> ev Hel σ0 <*> ev Her σ1)
                          [*] (ew Her σ1))
               μEntropy
               [*] (ew Hel σ0))
          μEntropy). {
    f_equal.
    extensionality σ0.
    f_equal.
    unfold option_map, plus_in, ew, ev.
    decide_eval Hel as [v0 w0 ex0 u0]; simpl; auto.
    rewrite <- Integration_linear_mult_l.
    nnr.
  } {
    evar (x : Entropy -> Entropy -> R+).
    replace (fun σ => eval_in (TCPlus Hel Her) A σ)
    with (fun σ => x (π 0 σ) (π 1 σ)); subst x. {
      rewrite pick_2_entropies.
      setoid_rewrite Integration_linear_mult_r at 1.
      reflexivity.
    } {
      extensionality σ.
      unfold eval_in, ew, ev.
      decide_eval (TCPlus _ _) as [v0 w0 ex0 u0]; simpl. {
        inversion ex0; subst; try absurd_Val.
        decide_eval Hel as [v3 w3 ex3 u3]; simpl.
        decide_eval Her as [v4 w4 ex4 u4]; simpl.

        specialize (u3 (_, _) X).
        specialize (u4 (_, _) X0).
        inversion u3; subst.
        inversion u4; subst.
        subst.

        unfold plus_in; simpl.
        rewrite nnr_mult_assoc.
        f_equal; try solve [nnr].
        f_equal.
        apply WT_Val_eq.
        simpl.
        auto.
      } {
        decide_eval Hel as [v3 w3 ex3 u3].
        decide_eval Her as [v4 w4 ex4 u4].
        contradict not_ex.
        pose proof (big_preservation Hel ex3).
        pose proof (big_preservation Her ex4).
        destruct v3 using Val_rect; try solve [inversion X].
        destruct v4 using Val_rect; try solve [inversion X0].
        eexists (_, _).
        refine (EPlus _ _ _); eauto.
      }
    }
  }
Qed.

Definition the_other_A_rel (τ : Ty) (A0 A1 : Event (WT_Val τ)) :=
  forall (v0 v1 : WT_Val τ) (Hv : V_rel τ v0 v1),
    (A0 v0 = (* iff *) A1 v1).

Definition narrow_event {τ} (A : Event (WT_Val τ)) : Event Val :=
  fun v =>
    match decidable_tc · v with
    | inl (existT _ τ' tc) =>
      match ty_eq_dec τ' τ with
      | left Heq => A (mk_WT_Val _ (rew Heq in tc))
      | right _ => false
      end
    | inr _ => false
    end.

Lemma narrow_cast_inverse τ (A : Event (WT_Val τ)) :
  (narrow_event A : Event (WT_Val τ)) = A .
Proof.
  extensionality v.
  destruct v.
  unfold narrow_event.
  simpl.
  destruct decidable_tc as [[]|]. {
    destruct ty_eq_dec. {
      subst.
      do 2 f_equal.
      compute.
      eapply tc_unique.
    } {
      contradict n.
      eapply expr_type_unique; eauto.
    }
  } {
    contradict n.
    repeat econstructor; eauto.
  }
Qed.

Lemma V_rel_implies_TC {τ v0 v1} :
  V_rel τ v0 v1 ->
  inhabited (TC · ⊢ v0 : τ) /\ inhabited (TC · ⊢ v1 : τ).
Proof.
  intros.
  destruct τ;
destruct v0 using Val_rect;
destruct v1 using Val_rect;
try contradiction H;
try solve [repeat constructor]. {
    inversion H as [[? ?] [? [? _]]].
    repeat subst.
    repeat econstructor; eauto.
  }
Qed.

Lemma convert_A_rel :
  forall {e0 e1 τ}
         {He0 : TC · ⊢ e0 : τ}
         {He1 : TC · ⊢ e1 : τ},
  (forall A0 A1 : Event Val,
      A_rel τ A0 A1 ->
      μ He0 A0 =
      μ  He1 A1) ->
         (forall A0 A1 : Event (WT_Val τ),
        the_other_A_rel τ A0 A1 ->
        μ He0 A0 =
        μ He1 A1).
Proof.
  intros.
  specialize (H (narrow_event A0) (narrow_event A1)).
  repeat rewrite narrow_cast_inverse in *.
  apply H.
  clear H.
  intros v0 v1 Hv.
  unfold narrow_event.
  repeat destruct decidable_tc; auto. {
    destruct s, s0.
    repeat destruct ty_eq_dec; subst; auto. {
      contradict n.
      destruct (V_rel_implies_TC Hv) as [[] []].
      eapply expr_type_unique; eauto.
    } {
      contradict n.
      destruct (V_rel_implies_TC Hv) as [[] []].
      eapply expr_type_unique; eauto.
    }
  } {
    contradict n.
    destruct (V_rel_implies_TC Hv) as [[] []].
    repeat econstructor; eauto.
  } {
    contradict n.
    destruct (V_rel_implies_TC Hv) as [[] []].
    repeat econstructor; eauto.
  }
Qed.

Lemma work_of_plus
      {el0 er0 el1 er1 : Expr}
      (Hel0 : TC · ⊢ el0 : ℝ)
      (Her0 : TC · ⊢ er0 : ℝ)
      (Hel1 : TC · ⊢ el1 : ℝ)
      (Her1 : TC · ⊢ er1 : ℝ)
      (Hl : forall Al0 Al1 : Event Val,
          A_rel ℝ Al0 Al1 ->
          μ Hel0 Al0 = μ Hel1 Al1)
      (Hr : forall Ar0 Ar1 : Event Val,
          A_rel ℝ Ar0 Ar1 ->
          μ Her0 Ar0 = μ Her1 Ar1)
      {A0 A1 : Event Val}
      (HA : A_rel ℝ A0 A1)
  : μ (TCPlus Hel0 Her0) A0 = μ (TCPlus Hel1 Her1) A1.
Proof.
  unfold μ.

  do 2 rewrite by_theorem_15_plus.

  pose proof convert_A_rel Hl as Hl'.
  pose proof convert_A_rel Hr as Hr'.

  apply (lemma_3 (the_other_A_rel ℝ)); intuition idtac.
  intros vl0 vl1 Hvl.
  unfold preimage.
  f_equal.

  apply (lemma_3 (the_other_A_rel ℝ)); intuition idtac.
  intros vr0 vr1 Hvr.
  unfold preimage.
  f_equal.

  destruct vl0 as [vl0 Hvl0].
  destruct vl1 as [vl1 Hvl1].
  destruct vr0 as [vr0 Hvr0].
  destruct vr1 as [vr1 Hvr1].

  destruct vl0 using Val_rect; try solve [inversion Hvl].
  destruct vl1 using Val_rect; try solve [inversion Hvl].
  destruct vr0 using Val_rect; try solve [inversion Hvr].
  destruct vr1 using Val_rect; try solve [inversion Hvr].
  simpl in *.

  inversion Hvl.
  inversion Hvr.
  subst.

  unfold plus_in; simpl.
  unfold Indicator.
  f_equal.
  apply HA.
  reflexivity.
Qed.

Lemma compat_plus Γ el0 er0 el1 er1 :
  (EXP Γ ⊢ el0 ≈ el1 : ℝ) ->
  (EXP Γ ⊢ er0 ≈ er1 : ℝ) ->
  (EXP Γ ⊢ e_plus el0 er0 ≈ e_plus el1 er1 : ℝ).
Proof.
  intros Hl Hr.

  destruct Hl as [tc_l0 tc_l1 Hl].
  destruct Hr as [tc_r0 tc_r1 Hr].
  simpl in *.
  refine (mk_related_exprs (TCPlus tc_l0 tc_r0) (TCPlus tc_l1 tc_r1) _).
  simpl in *.
  intros ρ0 ρ1 Hρ.

  specialize (Hl _ _ Hρ).
  specialize (Hr _ _ Hρ).

  destruct Hl as [tc_l0' [tc_l1' Hl]].
  destruct Hr as [tc_r0' [tc_r1' Hr]].

  exists (TCPlus tc_l0' tc_r0').
  exists (TCPlus tc_l1' tc_r1').

  intros A0 A1 HA.

  apply work_of_plus; auto.
Qed.

Program Definition apply_in {τa τr} (A : Event (WT_Val τr))
        (vf : WT_Val (τa ~> τr))
        (va : WT_Val τa)
        (σ : Entropy)
  : R+ :=
  WT_Val_rect
    (fun v => R+)
    (fun r τeq => False_rect _ _)
    (fun τa' τr' τeq body Hbody => eval_in (ty_subst1 va Hbody) A σ)
    vf.

(* ugly, ugly proof *)
Lemma elim_apply_in {τa τr}
      (* (body : Expr *)
      (* (Hbody : TC (extend · τa) ⊢ body : τr) *)
      (vlam : WT_Val (τa ~> τr))
      (va : WT_Val τa)
  : {body : Expr &
    {Hbody : (TC (extend · τa) ⊢ body : τr) &
     (vlam : Expr) = e_lam τa body /\
     forall (A : Event (WT_Val τr)),
       apply_in A vlam va =
       eval_in (ty_subst1 va Hbody) A}}.
Proof.
  destruct vlam using (@WT_Val_rect (τa ~> τr)); inversion τeq; subst.
  exists body.
  exists Hbody.
  intros.

  intuition idtac.
  extensionality σ.
  simpl.
  unfold eq_rect_r.
  repeat
    (match goal with
     | [ |- context[ rew ?H in _ ] ] =>
       let z := type of H in
       replace H with (eq_refl : z) by apply proof_irrelevance
     end; simpl).
  auto.
Qed.

(* ok, let's never look inside apply_in ever again. It's too ugly *)
Global Opaque apply_in.

Ltac do_elim_apply_in :=
  match goal with
  | [ |- context[ apply_in ?A ?vlam ?va ] ] =>
    let body := fresh "body" in
    let Hbody := fresh "H" body in
    let Hvf_body := fresh "Hvf_body" in
    let H := fresh "H" in
    destruct (elim_apply_in vlam va) as [body [Hbody [Hvf_body H]]];
    try (rewrite H;
         inversion Hvf_body;
         clear H Hvf_body)
  end.

Lemma by_theorem_15_app {ef ea τa τr} A
  (Hef : TC · ⊢ ef : (τa ~> τr))
  (Hea : TC · ⊢ ea : τa) :
    Integration (fun σ => eval_in (TCApp Hef Hea) A σ) μEntropy =
    Integration (fun vf =>
    Integration (fun va =>
    Integration (fun σ2 =>
                   apply_in A vf va σ2
                ) μEntropy
                ) (μ Hea)
                ) (μ Hef).
Proof.
  setoid_rewrite theorem_15; eauto.
  setoid_rewrite theorem_15; eauto.

  replace (Integration _ μEntropy)
  with (Integration
          (fun σ0 =>
             Integration
               (fun σ1 =>
                  Integration
                    (fun σ2 =>
                       option0 (apply_in A <$> ev Hef σ0 <*> ev Hea σ1 <*> Some σ2))
                    μEntropy
                    [*] ew Hea σ1)
               μEntropy
               [*] ew Hef σ0)
          μEntropy). {
    f_equal.
    extensionality σ0.
    f_equal.
    unfold option_map, ew, ev.
    decide_eval Hef as [v0 w0 ex0 u0]; simpl. {
      f_equal.
      extensionality σ1.
      decide_eval Hea as [v1 w1 ex1 u1]; simpl; auto.
    } {
      rewrite <- Integration_linear_mult_l.
      erewrite int_const_entropy; auto.
      nnr.
    }
  } {
    evar (x : Entropy -> Entropy -> Entropy -> R+).
    replace (fun σ => eval_in (TCApp Hef Hea) A σ)
    with (fun σ => x (π 0 σ) (π 1 σ) (π 2 σ)); subst x. {
      rewrite pick_3_entropies.
      f_equal.
      extensionality σ0.
      rewrite Integration_linear_mult_r.
      f_equal.
      extensionality σ1.
      rewrite 2 Integration_linear_mult_r.
      f_equal.
      reflexivity.
    } {
      extensionality σ.
      unfold eval_in, ev, ew.
      decide_eval (TCApp _ _) as [v0 w0 ex0 u0]; simpl. {
        inversion ex0; subst; try absurd_Val.
        decide_eval Hef as [v4 w4 ex4 u4]; simpl.
        decide_eval Hea as [v5 w5 ex5 u5]; simpl.
        do_elim_apply_in.

        specialize (u4 (_, _) X).
        specialize (u5 (_, _) X0).
        inversion u4; subst.
        inversion u5; subst.
        inversion H1; subst.

        unfold eval_in, ev, ew.

        decide_eval _ as [v6 w6 ex6 u6]. {
          simpl.

          do 2 set (mk_WT_Val _ _).

          specialize (u6 (v0, w3) X1).
          inversion u6; subst.
          enough (w = w0) by (rewrite H; nnr).
          subst w w0.
          apply WT_Val_eq; simpl.
          auto.
        }
      } {
        decide_eval Hef as [v3 w3 ex3 u3].
        decide_eval Hea as [v4 w4 ex4 u4].
        destruct v3 using Val_rect. {
          set (big_preservation _ _).
          inversion t.
        } {
          simpl.
          do_elim_apply_in; subst.
          unfold eval_in, ev, ew; simpl.

          decide_eval _ as [v5 w5 ex5 u5].
          contradict not_ex.
          eexists (_, _).
          econstructor; eauto.
        }
      }
    }
  }
Qed.

Lemma work_of_app {τa τr}
      {ef0 ea0 ef1 ea1 : Expr}
      (Hef0 : TC · ⊢ ef0 : τa ~> τr)
      (Hea0 : TC · ⊢ ea0 : τa)
      (Hef1 : TC · ⊢ ef1 : τa ~> τr)
      (Hea1 : TC · ⊢ ea1 : τa)
      (Hf : forall Af0 Af1 : Event Val,
          A_rel (τa ~> τr) Af0 Af1 ->
          μ Hef0 Af0 = μ Hef1 Af1)
      (Ha : forall Aa0 Aa1 : Event Val,
          A_rel τa Aa0 Aa1 ->
          μ Hea0 Aa0 = μ Hea1 Aa1)
      {A0 A1 : Event Val}
      (HA : A_rel τr A0 A1)
  : μ (TCApp Hef0 Hea0) A0 = μ (TCApp Hef1 Hea1) A1.
Proof.
  pose proof convert_A_rel Hf as Hf'.
  pose proof convert_A_rel Ha as Ha'.

  unfold μ.

  do 2 rewrite by_theorem_15_app.

  apply (lemma_3 (the_other_A_rel (τa ~> τr))); intuition idtac.
  intros vf0 vf1 Hvf.
  unfold preimage.
  f_equal.

  apply (lemma_3 (the_other_A_rel τa)); intuition idtac.
  intros va0 va1 Hva.
  unfold preimage.
  f_equal.

  destruct vf0 using WT_Val_rect; try contradiction.
  destruct vf1 using WT_Val_rect; try contradiction.

  simpl in *.
  hnf in Hvf.
  destruct Hvf as [_ [_ [_ Hvf]]].
  specialize (Hvf va0 va1 Hva).
  destruct Hvf as [tc_body0 [tc_body1 Hvf]].
  specialize (Hvf A0 A1 HA).

  do_elim_apply_in.
  do_elim_apply_in.
  subst.
  replace (ty_subst1 _ _) with tc_body0 by apply tc_unique.
  replace (ty_subst1 _ _) with tc_body1 by apply tc_unique.
  apply Hvf.
Qed.

Lemma compat_app Γ ef0 ef1 ea0 ea1 τa τr :
  (EXP Γ ⊢ ef0 ≈ ef1 : (τa ~> τr)) ->
  (EXP Γ ⊢ ea0 ≈ ea1 : τa) ->
  (EXP Γ ⊢ e_app ef0 ea0 ≈ e_app ef1 ea1 : τr).
Proof.
  intros Hf Ha.

  destruct Hf as [tc_f0 tc_f1 Hf].
  destruct Ha as [tc_a0 tc_a1 Ha].
  simpl in *.
  refine (mk_related_exprs (TCApp tc_f0 tc_a0) (TCApp tc_f1 tc_a1) _).
  simpl.
  intros ρ0 ρ1 Hρ.

  specialize (Hf _ _ Hρ).
  specialize (Ha _ _ Hρ).
  destruct Hf as [tc_f0' [tc_f1' Hf]].
  destruct Ha as [tc_a0' [tc_a1' Ha]].

  eexists (TCApp tc_f0' tc_a0').
  eexists (TCApp tc_f1' tc_a1').
  intros A0 A1 HA.

  apply work_of_app; auto.
Qed.

Lemma compat_sample Γ :
  EXP Γ ⊢ e_sample ≈ e_sample : ℝ.
Proof.
  refine (mk_related_exprs TCSample TCSample _).
  simpl.
  intros ρ0 ρ1 Hρ.
  exists TCSample.
  exists TCSample.
  intros A0 A1 HA.

  unfold μ.
  f_equal.
  extensionality σ.

  unfold eval_in, ev, ew.

  decide_eval _ as [v0 w0 e0 u0].

  simpl.
  unfold Indicator.
  do 2 f_equal.
  apply HA.
  simpl.

  pose proof (big_preservation TCSample e0).
  destruct v0 using Val_rect; try solve [inversion X].
  reflexivity.
Qed.

Definition factor_in (A : Event (WT_Val ℝ)) (v : WT_Val ℝ) : R+ :=
  match (v : Expr) with
  | e_real r =>
    match Rle_dec 0 r with
    | left rpos => Indicator A (v_real r) [*] mknnr r rpos
    | _ => nnr_0
    end
  | _ => nnr_0
  end.

Lemma by_theorem_15_factor {e} A
      (He : (TC · ⊢ e : ℝ)) :
  Integration (fun σ => eval_in (TCFactor He) A σ) μEntropy =
    Integration (factor_in A) (μ He).
Proof.
  setoid_rewrite theorem_15; eauto.

  integrand_extensionality σ.
  unfold option_map, factor_in, eval_in, ev, ew.

  decide_eval _ as [v0 w0 ex0 u0]. {
    inversion ex0; try absurd_Val.
    subst.
    decide_eval _ as [v1 w1 ex1 u1].
    pose proof (big_preservation He ex1).
    destruct v1 using Val_rect; try solve [inversion X0].
    simpl.
    injection (u1 (_, _) X); intros.
    subst.
    destruct Rle_dec; [| contradiction].
    set (mk_WT_Val _ _).
    rewrite (@WT_Val_eq _ (v_real r) w0); [nnr |].
    auto.
  } {
    simpl.
    decide_eval _ as [v1 w1 ex1 u1].
    simpl.
    destruct v1 using Val_rect; try solve [nnr].
    simpl.
    destruct Rle_dec; try solve [nnr].

    contradict not_ex.
    eexists (v_real r : Val, _).
    eapply EFactor with (rpos := r0).
    eauto.
  }
Qed.

Lemma work_of_factor
  (e0 e1 : Expr)
  (He0 : TC · ⊢ e0 : ℝ)
  (He1 : TC · ⊢ e1 : ℝ)
  (He : forall A0 A1 : Event Val,
      A_rel' ℝ (V_rel ℝ) A0 A1 ->
      μ He0 A0 = μ He1 A1)
  (A0 A1 : Event Val)
  (HA : A_rel' ℝ (V_rel ℝ) A0 A1) :
  μ (TCFactor He0) A0 = μ (TCFactor He1) A1.
Proof.
  pose proof convert_A_rel He as He'.

  unfold μ.

  rewrite (by_theorem_15_factor _ He0).
  rewrite (by_theorem_15_factor _ He1).


  apply (lemma_3 (the_other_A_rel ℝ)); intuition idtac.
  intros v0 v1 Hv.
  unfold preimage.
  f_equal.

  destruct v0 using (@WT_Val_rect ℝ); try discriminate.
  destruct v1 using (@WT_Val_rect ℝ); try discriminate.
  simpl in *.

  unfold factor_in.
  simpl.
  clear τeq τeq0.

  inversion Hv.
  subst.

  destruct Rle_dec; auto.
  unfold Indicator.
  simpl.
  do 2 f_equal.
  apply HA.
  exact Hv.
Qed.

Lemma compat_factor Γ e0 e1:
  (EXP Γ ⊢ e0 ≈ e1 : ℝ) ->
  (EXP Γ ⊢ e_factor e0 ≈ e_factor e1 : ℝ).
Proof.
  intro He.
  destruct He as [TC0 TC1 He].
  refine (mk_related_exprs (TCFactor TC0) (TCFactor TC1) _).

  intros ρ0 ρ1 Hρ.

  specialize (He _ _ Hρ).
  destruct He as [TC0' [TC1' He]].

  exists (TCFactor TC0').
  exists (TCFactor TC1').
  intros A0 A1 HA.

  apply work_of_factor; auto.
Qed.

Lemma fundamental_property {Γ e τ} :
  (TC Γ ⊢ e : τ) ->
  (EXP Γ ⊢ e ≈ e : τ).
Proof.
  intros tc.
  induction tc.
  - apply compat_real.
  - apply compat_var; tauto.
  - apply compat_lam; tauto.
  - apply compat_app with (τa := τa); tauto.
  - apply compat_factor; tauto.
  - apply compat_sample.
  - apply compat_plus; tauto.
Qed.

Lemma fundamental_of_nil {e τ} (He : (TC · ⊢ e : τ)) :
  forall A0 A1,
    A_rel τ A0 A1 ->
    μ He A0 = μ He A1.
Proof.
  destruct (fundamental_property He) as [_ _ H].
  specialize (H _ _ G_rel_nil).
  assert (subst_of_WT_Env WT_nil = ids) by auto.
  rewrite H0 in H.
  rewrite subst_id in H.
  destruct H as [? [? H]].
  rewrite (tc_unique x He) in H.
  rewrite (tc_unique x0 He) in H.
  apply H.
Qed.

Print Assumptions fundamental_property.

Lemma fundamental_property_of_values (v : Val) τ :
  (TC · ⊢ v : τ) ->
  (V_rel τ v v).
Proof.
  intros.
  destruct v using Val_rect; simpl in *. {
    inversion X; subst.
    reflexivity.
  } {
    inversion X; subst.
    split; auto.
    exists X0.
    exists X0.
    intros.
    pose proof fundamental_property X0.
    destruct X1 as [_ _ X1].
    pose (ρ0 := extend_WT_Env WT_nil va0).
    pose (ρ1 := extend_WT_Env WT_nil va1).
    specialize (X1 ρ0 ρ1).
    assert (G_rel (extend · τa) ρ0 ρ1). {
      hnf.
      intros.
      destruct x; try discriminate.
      inversion H0.
      inversion H1.
      inversion H2.
      subst.
      auto.
    }
    specialize (X1 X2).
    clear X2.

    destruct WT_nil as [? Hnil].
    inversion Hnil; subst.
    auto.
  }
Qed.
