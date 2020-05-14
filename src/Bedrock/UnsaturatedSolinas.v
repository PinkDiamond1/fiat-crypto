Require Import Coq.ZArith.ZArith.
Require Import Coq.Strings.String.
Require Import Coq.micromega.Lia.
Require Import coqutil.Byte.
Require Import coqutil.Word.Interface.
Require Import coqutil.Word.Properties.
Require Import coqutil.Map.Interface.
Require Import coqutil.Map.Properties.
Require Import coqutil.Tactics.Tactics.
Require Import bedrock2.Array.
Require Import bedrock2.ProgramLogic.
Require Import bedrock2.Scalars.
Require Import bedrock2.Syntax.
Require Import bedrock2.WeakestPrecondition.
Require Import bedrock2.WeakestPreconditionProperties.
Require Import bedrock2.Map.Separation.
Require Import bedrock2.Map.SeparationLogic.
Require Import Crypto.Arithmetic.Core.
Require Import Crypto.BoundsPipeline.
Require Import Crypto.Bedrock.ByteBounds.
Require Import Crypto.Bedrock.Defaults.
Require Import Crypto.Bedrock.Tactics.
Require Import Crypto.Bedrock.Types.
Require Import Crypto.Bedrock.MakeAccessSizes.
Require Import Crypto.Bedrock.MakeNames.
Require Import Crypto.Bedrock.MakeListLengths.
Require Import Crypto.Bedrock.MaxBounds.
Require Import Crypto.Bedrock.Util.
Require Import Crypto.Bedrock.VarnameGenerator.
Require Import Crypto.Bedrock.Proofs.Func.
Require Import Crypto.Bedrock.Translation.Func.
Require Import Crypto.COperationSpecifications.
Require Import Crypto.PushButtonSynthesis.UnsaturatedSolinas.
Require Import Crypto.Util.ListUtil.
Require Import Crypto.Util.ZUtil.Modulo.
Require Import Crypto.Language.API.
Require Import Coq.Lists.List. (* after SeparationLogic *)

Import Language.Compilers.
Import Types Types.Notations.
Existing Instances rep.Z rep.listZ_mem.

Import Language.Compilers.
Import Language.Wf.Compilers.
Import Associational Positional.

Require Import Crypto.Util.Notations.
Import Types.Notations ListNotations.
Import QArith_base.
Local Open Scope Z_scope.
Local Open Scope string_scope.

Local Coercion Z.of_nat : nat >-> Z.
Local Coercion inject_Z : Z >-> Q.
Local Coercion Z.pos : positive >-> Z.

Section __.
  Context {p : Types.parameters}
          {inname_gen outname_gen : nat -> string}
          (n : nat) (s : Z) (c : list (Z * Z)).
  Context (carry_mul_name add_name to_bytes_name : string).

  Definition make_bedrock_func_with_sizes
             {t} insize outsize (res : API.Expr t)
    : list string * list string * cmd.cmd :=
    fst (translate_func res
                        (make_innames (inname_gen:=inname_gen) _)
                        (list_lengths_repeat_args n _)
                        (access_sizes_repeat_args insize _)
                        (make_outnames (outname_gen:=outname_gen) _)
                        (access_sizes_repeat_base outsize _)).

  Definition make_bedrock_func {t} (res : API.Expr t)
    : list string * list string * cmd.cmd :=
    make_bedrock_func_with_sizes
      (t:=t) access_size.word access_size.word res.

  Definition carry_mul
             (res : API.Expr (type.arrow type_listZ
                                         (type.arrow type_listZ
                                                     type_listZ)))
    : bedrock_func :=
    (carry_mul_name, make_bedrock_func res).

  Definition add
             (res : API.Expr (type.arrow type_listZ
                                         (type.arrow type_listZ
                                                     type_listZ)))
    : bedrock_func :=
    (add_name, make_bedrock_func res).

  Definition to_bytes
             (res : API.Expr (type.arrow type_listZ type_listZ))
    : bedrock_func :=
    (to_bytes_name, make_bedrock_func_with_sizes
                      access_size.word access_size.one res).

  Section Proofs.
    Context {ok : Types.ok}.
    Existing Instance semantics_ok.

    Local Notation M := (s - Associational.eval c)%Z.
    Definition weight :=
      (ModOps.weight
         (Qnum (inject_Z (Z.log2_up M) / inject_Z (Z.of_nat n)))
         (QDen (inject_Z (Z.log2_up M) / inject_Z (Z.of_nat n)))).
    Local Notation eval := (eval weight n).
    Local Notation loose_bounds := (UnsaturatedSolinas.loose_bounds n s c).
    Local Notation tight_bounds := (UnsaturatedSolinas.tight_bounds n s c).
    Local Notation limbwidth :=
      (Z.log2_up (s - Associational.eval c) / Z.of_nat n)%Q.
    Local Notation n_bytes :=
      (Freeze.bytes_n (Qnum limbwidth) (Qden limbwidth) n).

    Context
      (* loose_bounds_ok could be proven in parameterized form, but is a pain
      and is easily computable with parameters plugged in. So for now, leaving
      as a precondition. *)
      (loose_bounds_ok :
         ZRange.type.option.is_tighter_than
           (t:=type_listZ) (Some loose_bounds)
           (Some (max_bounds n)) = true)
      (check_args_ok :
         check_args n s c Semantics.width (ErrorT.Success tt)
         = ErrorT.Success tt).

    Context (inname_gen_varname_gen_ok : disjoint inname_gen varname_gen)
            (outname_gen_varname_gen_ok : disjoint outname_gen varname_gen)
            (outname_gen_inname_gen_ok : disjoint outname_gen inname_gen).
    Context (inname_gen_unique : unique inname_gen)
            (outname_gen_unique : unique outname_gen).

    (* TODO : add length to Bignums and ByteArrays *)
    Definition Bignum : Semantics.word -> list Semantics.word -> Semantics.mem -> Prop :=
      array scalar (word.of_Z word_size_in_bytes).

    Definition EncodedBignum
      : Semantics.word -> list Byte.byte -> Semantics.mem -> Prop :=
      array ptsto (word.of_Z 1).

    Notation BignumSuchThat :=
      (fun addr ws P =>
         let xs := map word.unsigned ws in
         sep (emp (P xs)) (Bignum addr ws)).

    Notation EncodedBignumSuchThat :=
      (fun addr ws P =>
         let xs := map Byte.byte.unsigned ws in
         sep (emp (P xs)) (EncodedBignum addr ws)).

    Lemma Bignum_of_bytes addr bs :
      length bs = (n * Z.to_nat word_size_in_bytes)%nat ->
      Lift1Prop.iff1
        (array ptsto (word.of_Z 1) addr bs)
        (Bignum addr (map word.of_Z
                          (eval_bytes (width:=Semantics.width) bs))).
    Admitted. (* TODO *)

    Lemma Bignum_to_bytes addr x :
      list_Z_bounded_by (max_bounds n) (map word.unsigned x) ->
      Lift1Prop.iff1
        (Bignum addr x)
        (array ptsto (word.of_Z 1) addr (encode_bytes x)).
    Admitted. (* TODO *)

    Lemma relax_to_max_bounds x :
      list_Z_bounded_by loose_bounds x ->
      list_Z_bounded_by (max_bounds n) x.
    Proof. apply relax_list_Z_bounded_by; auto. Qed.

    Lemma bounded_by_loose_bounds_length x :
      list_Z_bounded_by loose_bounds x -> length x = n.
    Proof.
      intros. pose proof length_list_Z_bounded_by _ _ ltac:(eassumption).
      rewrite length_loose_bounds in *. lia.
    Qed.

    Ltac crush_list_ptr_subgoals :=
      repeat match goal with
             | _ => progress cbv [WeakestPrecondition.literal]
             | _ => rewrite word.of_Z_unsigned
             | _ => rewrite map.get_put_diff by congruence
             | _ => rewrite map.get_put_same by auto
             | |- WeakestPrecondition.get _ _ _ => eexists
             | _ => eapply max_bounds_range_iff;
                    solve [auto using relax_to_max_bounds, relax_correct]
             | _ => solve [apply word.unsigned_range]
             | _ => solve [auto using eval_bytes_range]
             | _ => reflexivity
             end.
    Ltac exists_list_ptr p :=
      exists p; sepsimpl; [ ];
             eexists; sepsimpl;
             [ solve [crush_list_ptr_subgoals] .. | ];
             eexists; sepsimpl;
             [ solve [crush_list_ptr_subgoals] .. | ].
    Ltac next_argument :=
      (exists 1%nat); sepsimpl; cbn [firstn skipn];
      [ solve [eauto using firstn_length_le] | ].
    Ltac prove_bounds_direct :=
      match goal with
      | H : _ |- _ => apply H; solve [auto]
      end.
    Ltac assert_bounds x :=
      match goal with
      | H: list_Z_bounded_by ?bs x |- _ => idtac
      | _ => assert (list_Z_bounded_by tight_bounds x) by prove_bounds_direct
      | _ => assert (list_Z_bounded_by loose_bounds x) by prove_bounds_direct
      | _ => assert (list_Z_bounded_by (max_bounds n) x) by prove_bounds_direct
      | _ => fail "could not determine known bounds of " x
      end.
    Ltac prove_bounds :=
      match goal with |- list_Z_bounded_by ?bs ?x => assert_bounds x end;
      match goal with
      | H : list_Z_bounded_by ?b1 ?x |- list_Z_bounded_by ?b2 ?x =>
        first [ unify b1 b2; apply H
              | unify b1 tight_bounds; unify b2 (max_bounds n);
                apply relax_to_max_bounds, relax_correct; apply H
              | unify b1 tight_bounds; unify b2 loose_bounds;
                apply relax_correct; apply H
              | unify b1 loose_bounds; unify b2 (max_bounds n);
                apply relax_to_max_bounds; apply H ]
      end.

    (* TODO: figure where to put this and if we want to do this strategy *)
    Definition Solinas_carry_mul_correct x y out :=
      eval out mod M = (Z.mul (eval x) (eval y)) mod M
      /\ list_Z_bounded_by tight_bounds out.
    Lemma carry_mul_correct_iff carry_mul :
      Solinas.carry_mul_correct
        weight n M tight_bounds loose_bounds carry_mul
      <-> (forall x y,
              list_Z_bounded_by loose_bounds x ->
              list_Z_bounded_by loose_bounds y ->
              Solinas_carry_mul_correct x y (carry_mul x y)).
    Proof. reflexivity. Qed.

    Definition Solinas_add_correct x y out :=
      eval out mod M = (Z.add (eval x) (eval y)) mod M
      /\ list_Z_bounded_by loose_bounds out.
    Lemma add_correct_iff add :
      Solinas.add_correct
        weight n M tight_bounds loose_bounds add
      <-> (forall x y,
              list_Z_bounded_by tight_bounds x ->
              list_Z_bounded_by tight_bounds y ->
              Solinas_add_correct x y (add x y)).
    Proof. reflexivity. Qed.

    Definition Solinas_to_bytes_correct x out :=
      out = Partition.Partition.partition (ModOps.weight 8 1) n_bytes
                                          (eval x mod M).
    Lemma to_bytes_correct_iff to_bytes :
      Solinas.to_bytes_correct
        weight n n_bytes M tight_bounds to_bytes
      <-> (forall x,
              list_Z_bounded_by tight_bounds x ->
              Solinas_to_bytes_correct x (to_bytes x)).
    Proof. reflexivity. Qed.

    (* TODO: it would be good if the bounds could go within the correctness
       proposition, which only works if we can get the length of the output in
       some other way. *)

    (* For out, you can get a Bignum from an array of bytes using
       Bignum_from_bytes. *)
    Definition spec_of_carry_mul name : spec_of name :=
      fun functions =>
        forall wx wy px py pout wold_out t m
               (Ra Rr : Semantics.mem -> Prop),
          sep (sep (BignumSuchThat px wx (list_Z_bounded_by loose_bounds))
                   (BignumSuchThat py wy (list_Z_bounded_by loose_bounds)))
              Ra m ->
          sep (BignumSuchThat pout wold_out (fun l => length l = n))
              Rr m ->
          let post := Solinas_carry_mul_correct (map word.unsigned wx)
                                                (map word.unsigned wy) in
          WeakestPrecondition.call
            functions name t m
            (px :: py :: pout :: nil)
            (fun t' m' rets =>
               t = t' /\
               rets = []%list /\
               exists wout,
                 sep (BignumSuchThat pout wout post) Rr m').

    Definition spec_of_add name : spec_of name :=
      fun functions =>
        forall wx wy px py pout wold_out t m
               (Ra Rr : Semantics.mem -> Prop),
          sep (sep (BignumSuchThat px wx (list_Z_bounded_by tight_bounds))
                   (BignumSuchThat py wy (list_Z_bounded_by tight_bounds)))
              Ra m ->
          sep (BignumSuchThat pout wold_out (fun l => length l = n))
              Rr m ->
          let post := Solinas_add_correct (map word.unsigned wx)
                                          (map word.unsigned wy) in
          WeakestPrecondition.call
            functions name t m
            (px :: py :: pout :: nil)
            (fun t' m' rets =>
               t = t' /\
               rets = []%list /\
               exists wout,
                 sep (BignumSuchThat pout wout post) Rr m').

    Definition spec_of_to_bytes name : spec_of name :=
      fun functions =>
        forall px wx pout wold_out t m
               (Ra Rr : Semantics.mem -> Prop),
          sep (BignumSuchThat
                 px wx (list_Z_bounded_by tight_bounds)) Ra m ->
          sep (EncodedBignumSuchThat pout wold_out
                                     (fun l => length l = n_bytes))
              Rr m ->
          let post := Solinas_to_bytes_correct (map word.unsigned wx) in
          WeakestPrecondition.call
            functions name t m
            (px :: pout :: nil)
            (fun t' m' rets =>
               t = t' /\
               rets = []%list /\
               exists wout : list Byte.byte,
                 sep (EncodedBignumSuchThat pout wout post) Rr m').

    Lemma carry_mul_correct :
      forall carry_mul_res :
               API.Expr (type_listZ -> type_listZ -> type_listZ),
        UnsaturatedSolinas.carry_mul n s c Semantics.width
        = ErrorT.Success carry_mul_res ->
        expr.Wf3 carry_mul_res ->
        valid_func (carry_mul_res (fun _ : API.type => unit)) ->
        forall functions,
          spec_of_carry_mul carry_mul_name
            ((carry_mul carry_mul_res) :: functions).
    Proof.
      cbv [spec_of_carry_mul carry_mul make_bedrock_func]; intros.
      sepsimpl.

      (* get the carry_mul correctness proof *)
      match goal with H : _ = ErrorT.Success _ |- _ =>
                      apply UnsaturatedSolinas.carry_mul_correct in H;
                        [ | assumption ];
                        rewrite carry_mul_correct_iff in H;
                        specialize (H (_ wx) (_ wy)
                                      ltac:(eassumption) ltac:(eassumption))
      end.

      (* assert output length for convenience *)
      match goal with
        H : context [Solinas_carry_mul_correct _ _ ?e] |- _ =>
        assert (length e = n)
          by (apply bounded_by_loose_bounds_length; prove_bounds)
      end.

      (* use translate_func_correct to get the translation postcondition *)
      eapply Proper_call;
        [ | eapply translate_func_correct with
                (Ra0:=Ra) (Rr0:=Rr) (out_ptrs:=[pout])
                (args:=(map word.unsigned wx, (map word.unsigned wy, tt)))
                (flat_args := [px; py]) ].

      { (* prove that the translation postcondition is sufficient *)
        repeat intro.
        match goal with
          H : context [sep _ _ ?m] |- context [_ ?m] =>
          cbn - [Memory.bytes_per translate_func] in H
        end.
        sepsimpl_hyps; ssplit; [ congruence | congruence | eexists ].
        fold Bignum in *.
        sepsimpl;
          [ erewrite map_unsigned_of_Z, map_word_wrap_bounded
            by (eapply max_bounds_range_iff; eauto);
            match goal with H : _ |- _ => apply H; assumption end | ].
        subst. cbv [Bignum expr.Interp].
        match goal with
        | H : literal (word.unsigned _) (eq _) |- _ =>
          inversion H as [H']; clear H;
            rewrite word.of_Z_unsigned in H'
        end.
        match goal with H : word.unsigned _ = word.unsigned _ |- _ =>
                        apply word.unsigned_inj in H end.
        (* TODO: without the below clear, subst fails, this is dumb *)
        repeat match goal with H : _ = n |- _ => clear H end.
        subst.
        match goal with
          H : map word.unsigned _ = ?l |- context [map word.of_Z ?l] =>
          rewrite <-H, map_of_Z_unsigned
        end.
        rewrite word_size_in_bytes_eq.
        use_sep_assumption.
        rewrite array_truncated_scalar_scalar_iff1.
        cancel. }

      (* Now, we prove translate_func preconditions.
         First, take care of all the easy ones. *)
      all: auto using make_innames_varname_gen_disjoint,
           make_outnames_varname_gen_disjoint,
           make_innames_make_outnames_disjoint,
           flatten_make_innames_NoDup, flatten_make_outnames_NoDup.

      { (* list lengths are correct *)
        cbn. rewrite !bounded_by_loose_bounds_length by auto using relax_correct.
        reflexivity. }
      { (* arg pointers are correct *)
        cbn - [Memory.bytes_per]; sepsimpl.
        next_argument. exists_list_ptr px.
        next_argument. exists_list_ptr py.
        cbv [Bignum] in *.
        repeat seprewrite array_truncated_scalar_scalar_iff1.
        rewrite <-word_size_in_bytes_eq.
        ecancel_assumption. }
      { (* input access sizes are legal *)
        pose proof bits_per_word_le_width.
        cbn - [Memory.bytes_per]; tauto. }
      { (* input access sizes are accurate *)
        cbn - [Memory.bytes_per]; ssplit; try tauto;
          eapply max_bounds_range_iff; prove_bounds. }
      { (* output access sizes are legal *)
        pose proof bits_per_word_le_width.
        cbn - [Memory.bytes_per]; tauto. }
      { (* output access sizes are accurate *)
        cbn - [Memory.bytes_per].
        eapply max_bounds_range_iff; prove_bounds. }
      { (* space is reserved for output lists *)
        cbn - [Memory.bytes_per]. sepsimpl.
        cbv [expr.Interp] in *. cbn [Compilers.base_interp] in *.
        exists (map word.unsigned wold_out).
        sepsimpl; [ rewrite map_length in *; congruence | ].
        exists pout; sepsimpl; [ ].
        match goal with
          H : Solinas_carry_mul_correct _ _ ?e |- _ =>
          assert (list_Z_bounded_by (max_bounds n) e) by prove_bounds
        end.
        eexists.
        sepsimpl; [ reflexivity
                  | rewrite bits_per_word_eq_width
                    by auto using width_0mod_8;
                    solve [apply Forall_map_unsigned]
                  | ].
        eexists.
        sepsimpl; [ reflexivity
                  | eexists; rewrite ?map.get_put_diff by congruence;
                    rewrite map.get_put_same; split; reflexivity
                  | ].
        cbv [Bignum] in *.
        rewrite <-word_size_in_bytes_eq.
        use_sep_assumption.
        rewrite array_truncated_scalar_scalar_iff1.
        cancel. }
    Qed.

    Lemma add_correct :
      forall add_res :
               API.Expr (type_listZ -> type_listZ -> type_listZ),
        UnsaturatedSolinas.add n s c Semantics.width
        = ErrorT.Success add_res ->
        expr.Wf3 add_res ->
        valid_func (add_res (fun _ : API.type => unit)) ->
        forall functions,
          spec_of_add add_name
            (add add_res :: functions).
    Proof.
      cbv [spec_of_add add make_bedrock_func]; intros.
      sepsimpl.

      (* get the add correctness proof *)
      match goal with H : _ = ErrorT.Success _ |- _ =>
                      apply UnsaturatedSolinas.add_correct in H;
                        [ | assumption ];
                        rewrite add_correct_iff in H;
                        specialize (H (_ wx) (_ wy)
                                      ltac:(eassumption) ltac:(eassumption))
      end.

      (* assert output length for convenience *)
      match goal with
        H : context [Solinas_add_correct _ _ ?e] |- _ =>
        assert (length e = n)
          by (apply bounded_by_loose_bounds_length; prove_bounds)
      end.

      (* use translate_func_correct to get the translation postcondition *)
      eapply Proper_call;
        [ | eapply translate_func_correct with
                (Ra0:=Ra) (Rr0:=Rr) (out_ptrs:=[pout])
                (args:=(map word.unsigned wx, (map word.unsigned wy, tt)))
                (flat_args := [px; py]) ].

      { (* prove that the translation postcondition is sufficient *)
        repeat intro.
        match goal with
          H : context [sep _ _ ?m] |- context [_ ?m] =>
          cbn - [Memory.bytes_per translate_func] in H
        end.
        sepsimpl_hyps; ssplit; [ congruence | congruence | eexists ].
        fold Bignum in *.
        sepsimpl;
          [ erewrite map_unsigned_of_Z, map_word_wrap_bounded
            by (eapply max_bounds_range_iff; eauto);
            match goal with H : _ |- _ => apply H; assumption end | ].
        subst. cbv [Bignum expr.Interp].
        match goal with
        | H : literal (word.unsigned _) (eq _) |- _ =>
          inversion H as [H']; clear H;
            rewrite word.of_Z_unsigned in H'
        end.
        match goal with H : word.unsigned _ = word.unsigned _ |- _ =>
                        apply word.unsigned_inj in H end.
        (* TODO: without the below clear, subst fails, this is dumb *)
        repeat match goal with H : _ = n |- _ => clear H end.
        subst.
        match goal with
          H : map word.unsigned _ = ?l |- context [map word.of_Z ?l] =>
          rewrite <-H, map_of_Z_unsigned
        end.
        rewrite word_size_in_bytes_eq.
        use_sep_assumption.
        rewrite array_truncated_scalar_scalar_iff1.
        cancel. }

      (* Now, we prove translate_func preconditions.
         First, take care of all the easy ones. *)
      all: auto using make_innames_varname_gen_disjoint,
           make_outnames_varname_gen_disjoint,
           make_innames_make_outnames_disjoint,
           flatten_make_innames_NoDup, flatten_make_outnames_NoDup.

      { (* list lengths are correct *)
        cbn.
        rewrite !bounded_by_loose_bounds_length by auto using relax_correct.
        reflexivity. }
      { (* arg pointers are correct *)
        cbn - [Memory.bytes_per]; sepsimpl.
        next_argument. exists_list_ptr px.
        next_argument. exists_list_ptr py.
        cbv [Bignum] in *.
        repeat seprewrite array_truncated_scalar_scalar_iff1.
        rewrite <-word_size_in_bytes_eq.
        ecancel_assumption. }
      { (* input access sizes are legal *)
        pose proof bits_per_word_le_width.
        cbn - [Memory.bytes_per]; tauto. }
      { (* input access sizes are accurate *)
        cbn - [Memory.bytes_per]; ssplit; try tauto;
          eapply max_bounds_range_iff; prove_bounds. }
      { (* output access sizes are legal *)
        pose proof bits_per_word_le_width.
        cbn - [Memory.bytes_per]; tauto. }
      { (* output access sizes are accurate *)
        cbn - [Memory.bytes_per].
        eapply max_bounds_range_iff; prove_bounds. }
      { (* space is reserved for output lists *)
        cbn - [Memory.bytes_per]. sepsimpl.
        cbv [expr.Interp] in *. cbn [Compilers.base_interp] in *.
        cbn [Compilers.base_interp] in *.
        exists (map word.unsigned wold_out).
        sepsimpl; [ rewrite map_length in *; congruence | ].
        exists pout; sepsimpl; [ ].
        match goal with
          H : Solinas_add_correct _ _ ?e |- _ =>
          assert (list_Z_bounded_by (max_bounds n) e) by prove_bounds
        end.
        eexists.
        sepsimpl; [ reflexivity
                  | rewrite bits_per_word_eq_width
                    by auto using width_0mod_8;
                    solve [apply Forall_map_unsigned]
                  | ].
        eexists.
        sepsimpl; [ reflexivity
                  | eexists; rewrite ?map.get_put_diff by congruence;
                    rewrite map.get_put_same; split; reflexivity
                  | ].
        cbv [Bignum] in *.
        rewrite <-word_size_in_bytes_eq.
        use_sep_assumption.
        rewrite array_truncated_scalar_scalar_iff1.
        cancel. }
    Qed.

    Lemma to_bytes_correct :
      forall to_bytes_res :
               API.Expr (type_listZ -> type_listZ),
        UnsaturatedSolinas.to_bytes n s c Semantics.width
        = ErrorT.Success to_bytes_res ->
        expr.Wf3 to_bytes_res ->
        valid_func (to_bytes_res (fun _ : API.type => unit)) ->
        forall functions,
          spec_of_to_bytes to_bytes_name
            (to_bytes to_bytes_res :: functions).
    Proof.
      cbv [spec_of_to_bytes to_bytes make_bedrock_func]; intros.
      sepsimpl.

      (* get the to_bytes correctness proof *)
      match goal with H : _ = ErrorT.Success _ |- _ =>
                      apply UnsaturatedSolinas.to_bytes_correct in H;
                        [ | assumption ];
                        rewrite to_bytes_correct_iff in H;
                        specialize (H (_ wx) ltac:(eassumption))
      end.

      (* assert output length for convenience *)
      match goal with
        H : context [Solinas_to_bytes_correct _ ?e] |- _ =>
        assert (length e = n_bytes)
          by (cbn [Compilers.base_interp];
              erewrite <-Partition.length_partition;
              cbv [Solinas_to_bytes_correct] in H; rewrite <-H;
              congruence)
      end.

      (* assert output bounds for convenience *)
      match goal with
        H : context [Solinas_to_bytes_correct _ ?e] |- _ =>
        assert (list_Z_bounded_by (byte_bounds n_bytes) e)
          by (cbv [Solinas_to_bytes_correct] in H; rewrite H;
              apply partition_bounded_by)
      end.

      (* use translate_func_correct to get the translation postcondition *)
      eapply Proper_call;
        [ | eapply translate_func_correct with
                (Ra0:=Ra) (Rr0:=Rr) (out_ptrs:=[pout])
                (args:=(map word.unsigned wx, tt))
                (flat_args := [px]) ].

      { (* prove that the translation postcondition is sufficient *)
        repeat intro.
        match goal with
          H : context [sep _ _ ?m] |- context [_ ?m] =>
          cbn - [Memory.bytes_per translate_func] in H
        end.
        sepsimpl_hyps; ssplit; [ congruence | congruence | eexists ].
        fold Bignum in *.
        sepsimpl;
          [ erewrite byte_map_unsigned_of_Z, map_byte_wrap_bounded
            by (eapply byte_bounds_range_iff; eauto);
            match goal with H : _ |- _ => apply H; assumption end | ].
        subst. cbv [Bignum expr.Interp].
        match goal with
        | H : literal (word.unsigned _) (eq _) |- _ =>
          inversion H as [H']; clear H;
            rewrite word.of_Z_unsigned in H'
        end.
        match goal with H : word.unsigned _ = word.unsigned _ |- _ =>
                        apply word.unsigned_inj in H end.
        (* TODO: without the below clear, subst fails, this is dumb *)
        repeat match goal with H : _ = n |- _ => clear H end.
        subst.
        match goal with
          H : map word.unsigned _ = ?l |- context [?l] =>
          rewrite <-H end.
        change (Z.of_nat (Memory.bytes_per access_size.one)) with 1 in *.
        use_sep_assumption.
        rewrite array_truncated_scalar_ptsto_iff1.
        reflexivity. }

      (* Now, we prove translate_func preconditions.
         First, take care of all the easy ones. *)
      all: auto using make_innames_varname_gen_disjoint,
           make_outnames_varname_gen_disjoint,
           make_innames_make_outnames_disjoint,
           flatten_make_innames_NoDup, flatten_make_outnames_NoDup.

      { (* list lengths are correct *)
        cbn.
        rewrite !bounded_by_loose_bounds_length by auto using relax_correct.
        reflexivity. }
      { (* arg pointers are correct *)
        cbn - [Memory.bytes_per]; sepsimpl.
        next_argument. exists_list_ptr px.
        cbv [Bignum] in *.
        repeat seprewrite array_truncated_scalar_scalar_iff1.
        rewrite <-word_size_in_bytes_eq.
        ecancel_assumption. }
      { (* input access sizes are legal *)
        pose proof bits_per_word_le_width.
        cbn - [Memory.bytes_per]; tauto. }
      { (* input access sizes are accurate *)
        cbn - [Memory.bytes_per]; ssplit; try tauto;
          eapply max_bounds_range_iff; prove_bounds. }
      { (* output access sizes are legal *)
        cbn. apply width_ge_8. }
      { (* output access sizes are accurate *)
        cbn - [Memory.bytes_per]. cbv [expr.Interp] in *.
        eapply byte_bounds_range_iff; prove_bounds. }
      { (* space is reserved for output lists *)
        cbn - [Memory.bytes_per]. sepsimpl.
        cbv [expr.Interp] in *. cbn [Compilers.base_interp] in *.
        change (Z.of_nat (Memory.bytes_per access_size.one)) with 1.
        change (1 * 8)%Z with 8.
        exists (map byte.unsigned wold_out).
        sepsimpl; [ rewrite map_length in *; congruence | ].
        exists pout; sepsimpl; [ ].
        exists (map word.of_Z (map byte.unsigned wold_out)).
        sepsimpl;
          [ rewrite map_unsigned_of_Z;
            solve [eauto using map_word_wrap_bounded,
                   byte_unsigned_within_max_bounds]
          | solve [apply Forall_map_byte_unsigned] | ].
        eexists.
        sepsimpl; [ reflexivity
                  | eexists; rewrite ?map.get_put_diff by congruence;
                    rewrite map.get_put_same; split; reflexivity
                  | ].
        cbv [EncodedBignum] in *.
        rewrite map_unsigned_of_Z.
        erewrite map_word_wrap_bounded by auto using byte_unsigned_within_max_bounds.
        use_sep_assumption.
        rewrite array_truncated_scalar_ptsto_iff1.
        rewrite byte_map_of_Z_unsigned.
        cancel. }
    Qed.
  End Proofs.
End __.