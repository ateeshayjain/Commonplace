-- Manage Categories: readers can remove categories they added.
-- Without this policy a DELETE matches no rows under RLS and the category
-- comes back on the next load. Built-in rows (user_id null) stay.
CREATE POLICY "Users can delete own categories" ON categories
  FOR DELETE USING (auth.uid() = user_id AND is_system = false);
