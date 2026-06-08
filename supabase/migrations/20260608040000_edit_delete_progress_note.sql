-- Race-free edit/delete for progress notes.
--
-- Progress notes live as a JSON array in a single text column (quant_notes on
-- service_tickets; notes on audits/collocations). Appends already go through the
-- race-free append_progress_note RPC. Edits and deletes, however, were done in
-- the browser by rewriting the WHOLE array (read array -> splice by index ->
-- write array back). If two people touch the same record's notes at once, that
-- read-modify-write clobbers the other person's change, and an index can point
-- at the wrong note if the array shifted underneath it.
--
-- These two RPCs fix both: each is a single UPDATE that rebuilds the array
-- server-side, touching only the one element identified by its stable content
-- (at + by + text). Concurrent appends to other elements are preserved.

-- Shared note-identity: an element matches when its at/by/text all equal the
-- values the client last saw. Only the FIRST such element is changed (mirrors
-- the old index-based behavior if true duplicates somehow exist).

CREATE OR REPLACE FUNCTION public.edit_progress_note(
    record_kind text,
    record_id uuid,
    note_at text,
    note_by text,
    old_text text,
    new_text text,
    tagged_contacts text[] DEFAULT ARRAY[]::text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    arr jsonb;
    rebuilt jsonb;
    target_ord int;
BEGIN
    IF record_kind NOT IN ('service_ticket', 'audit', 'collocation') THEN
        RAISE EXCEPTION 'Invalid record_kind: %', record_kind;
    END IF;
    IF new_text IS NULL OR trim(new_text) = '' THEN
        RAISE EXCEPTION 'new_text is required';
    END IF;

    IF record_kind = 'service_ticket' THEN
        SELECT COALESCE(NULLIF(quant_notes, '')::jsonb, '[]'::jsonb) INTO arr
        FROM public.service_tickets WHERE id = record_id FOR UPDATE;
    ELSIF record_kind = 'audit' THEN
        SELECT COALESCE(NULLIF(notes, '')::jsonb, '[]'::jsonb) INTO arr
        FROM public.audits WHERE id = record_id FOR UPDATE;
    ELSE
        SELECT COALESCE(NULLIF(notes, '')::jsonb, '[]'::jsonb) INTO arr
        FROM public.collocations WHERE id = record_id FOR UPDATE;
    END IF;

    IF arr IS NULL THEN
        RAISE EXCEPTION 'No % found with id %', record_kind, record_id;
    END IF;

    SELECT min(ord) INTO target_ord
    FROM jsonb_array_elements(arr) WITH ORDINALITY AS t(elem, ord)
    WHERE elem->>'at' IS NOT DISTINCT FROM note_at
      AND elem->>'by' IS NOT DISTINCT FROM note_by
      AND elem->>'text' IS NOT DISTINCT FROM old_text;

    IF target_ord IS NULL THEN
        RAISE EXCEPTION 'Progress note not found (it may have been edited or deleted by someone else)';
    END IF;

    SELECT jsonb_agg(
        CASE WHEN ord = target_ord
             THEN jsonb_set(
                    jsonb_set(elem, '{text}', to_jsonb(new_text)),
                    '{taggedContacts}', COALESCE(to_jsonb(tagged_contacts), '[]'::jsonb)
                  )
             ELSE elem END
        ORDER BY ord)
    INTO rebuilt
    FROM jsonb_array_elements(arr) WITH ORDINALITY AS t(elem, ord);

    IF record_kind = 'service_ticket' THEN
        UPDATE public.service_tickets
        SET quant_notes = rebuilt::text, updated_at = now(), updated_by = auth.uid()
        WHERE id = record_id;
    ELSIF record_kind = 'audit' THEN
        UPDATE public.audits
        SET notes = rebuilt::text, updated_at = now(), updated_by = auth.uid()
        WHERE id = record_id;
    ELSE
        UPDATE public.collocations
        SET notes = rebuilt::text, updated_at = now(), updated_by = auth.uid()
        WHERE id = record_id;
    END IF;

    RETURN rebuilt;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_progress_note(
    record_kind text,
    record_id uuid,
    note_at text,
    note_by text,
    old_text text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    arr jsonb;
    rebuilt jsonb;
    target_ord int;
BEGIN
    IF record_kind NOT IN ('service_ticket', 'audit', 'collocation') THEN
        RAISE EXCEPTION 'Invalid record_kind: %', record_kind;
    END IF;

    IF record_kind = 'service_ticket' THEN
        SELECT COALESCE(NULLIF(quant_notes, '')::jsonb, '[]'::jsonb) INTO arr
        FROM public.service_tickets WHERE id = record_id FOR UPDATE;
    ELSIF record_kind = 'audit' THEN
        SELECT COALESCE(NULLIF(notes, '')::jsonb, '[]'::jsonb) INTO arr
        FROM public.audits WHERE id = record_id FOR UPDATE;
    ELSE
        SELECT COALESCE(NULLIF(notes, '')::jsonb, '[]'::jsonb) INTO arr
        FROM public.collocations WHERE id = record_id FOR UPDATE;
    END IF;

    IF arr IS NULL THEN
        RAISE EXCEPTION 'No % found with id %', record_kind, record_id;
    END IF;

    SELECT min(ord) INTO target_ord
    FROM jsonb_array_elements(arr) WITH ORDINALITY AS t(elem, ord)
    WHERE elem->>'at' IS NOT DISTINCT FROM note_at
      AND elem->>'by' IS NOT DISTINCT FROM note_by
      AND elem->>'text' IS NOT DISTINCT FROM old_text;

    IF target_ord IS NULL THEN
        RAISE EXCEPTION 'Progress note not found (it may have been edited or deleted by someone else)';
    END IF;

    SELECT COALESCE(jsonb_agg(elem ORDER BY ord) FILTER (WHERE ord <> target_ord), '[]'::jsonb)
    INTO rebuilt
    FROM jsonb_array_elements(arr) WITH ORDINALITY AS t(elem, ord);

    IF record_kind = 'service_ticket' THEN
        UPDATE public.service_tickets
        SET quant_notes = rebuilt::text, updated_at = now(), updated_by = auth.uid()
        WHERE id = record_id;
    ELSIF record_kind = 'audit' THEN
        UPDATE public.audits
        SET notes = rebuilt::text, updated_at = now(), updated_by = auth.uid()
        WHERE id = record_id;
    ELSE
        UPDATE public.collocations
        SET notes = rebuilt::text, updated_at = now(), updated_by = auth.uid()
        WHERE id = record_id;
    END IF;

    RETURN rebuilt;
END;
$$;

GRANT EXECUTE ON FUNCTION public.edit_progress_note(text, uuid, text, text, text, text, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_progress_note(text, uuid, text, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
